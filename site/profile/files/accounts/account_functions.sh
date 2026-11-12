#!/bin/bash

kexec () {
    local TMP_KRB_CACHE CMD_EXIT_CODE
    TMP_KRB_CACHE=$(mktemp) || return 1
    if kinit -kt /etc/krb5.keytab -c "${TMP_KRB_CACHE}" &> /dev/null; then
        KRB5CCNAME="${TMP_KRB_CACHE}" "${@}"
        CMD_EXIT_CODE=$?
        kdestroy -c "${TMP_KRB_CACHE}" &> /dev/null
    else
        CMD_EXIT_CODE=1
    fi
    rm -f "${TMP_KRB_CACHE}"
    return $CMD_EXIT_CODE
}

# Wait for this request, excluding older connections that reused its conn/op IDs.
wait_for_result () {
    local conn=$1 op_id=$2 timestamp=$3
    local request_line result tail_pid
    request_line=$(grep -n -m 1 -F "${timestamp}" "${SLAPD_LOG_FILE}" | cut -d: -f1)
    if [[ -z "${request_line}" ]]; then
        echo "WARN::${0##*/} conn=${conn} op=${op_id}: request no longer present in access log"
        return 1
    fi
    {
        tail_pid=$!
        result=$(grep --line-buffered -m 1 -F "conn=${conn} op=${op_id} RESULT ")
        kill "${tail_pid}" 2> /dev/null
        wait "${tail_pid}" 2> /dev/null
    } < <(tail -n +${request_line} -F "${SLAPD_LOG_FILE}" 2> /dev/null)
    [[ "${result}" == *" RESULT err=0 "* ]]
}

wait_for_slurm() {
    local RETRY_DELAY="${WAIT_FOR_SLURM_RETRY_DELAY:-15}"
    while : ; do
        CLUSTER_INFO=$(/opt/software/slurm/bin/sacctmgr list cluster -n -P 2> /dev/null)
        if [ -z ${CLUSTER_INFO} ]; then
            echo "WARN::${FUNCNAME} cannot not connect to SlurmDBD, waiting ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        else
            break
        fi
    done
}

# Retrieve POSIX attributes into the caller's local USER_UID, USER_GID and USER_HOME.
get_user_info () {
    local USERNAME=$1 USER_INFO
    USER_UID= USER_GID= USER_HOME=
    USER_INFO=$(ldapsearch -Y EXTERNAL -H "${LDAP_URI}" -Q -o ldif-wrap=no -LLL -s base \
        -b "uid=${USERNAME},cn=users,cn=accounts,${BASEDN}" '(objectClass=posixAccount)' \
        uidNumber gidNumber homeDirectory) || return $?
    USER_UID=$(sed -n 's/^uidNumber: //p' <<< "${USER_INFO}")
    USER_GID=$(sed -n 's/^gidNumber: //p' <<< "${USER_INFO}")
    USER_HOME=$(sed -n 's/^homeDirectory: //p' <<< "${USER_INFO}")
}

mkhome () {
    local USERNAME=$1

    if [ -z "${USERNAME}" ]; then
        echo "ERROR::${FUNCNAME}: username unspecified"
        return 3
    fi

    local USER_UID USER_GID USER_HOME
    if ! get_user_info "${USERNAME}"; then
        echo "ERROR::${FUNCNAME} ${USERNAME}: could not retrieve user attributes from LDAP"
        return 1
    fi

    if [[ ! "${USER_UID}" =~ ^[0-9]+$ ]]; then
        echo "ERROR::${FUNCNAME} ${USERNAME}: UID not defined or invalid in LDAP"
        return 1
    fi

    if [[ ! "${USER_GID}" =~ ^[0-9]+$ ]]; then
        echo "ERROR::${FUNCNAME} ${USERNAME}: GID not defined or invalid in LDAP"
        return 1
    fi

    if [ -z "${USER_HOME}" ]; then
        echo "ERROR::${FUNCNAME} ${USERNAME}: home path not defined in LDAP"
        return 1
    fi

    # Home folder can be created by modproject function, but it will only create ~/project folder
    # and not the dot files and other files from /etc/skel.ipa
    if [[ -d "${USER_HOME}" && -n "$(find "${USER_HOME}" -mindepth 1 -maxdepth 1 -not -path "${USER_HOME}/projects")" ]]; then
        local SUCCESS_LOG="INFO::${FUNCNAME} ${USERNAME}: synced ${USER_HOME} (home already created)"
    else
        local SUCCESS_LOG="INFO::${FUNCNAME} ${USERNAME}: created ${USER_HOME}"
    fi

    if ! rsync -opg -r -l --ignore-existing --chown=$USER_UID:$USER_GID --chmod=Dg-rwx,o-rwx,Fg-rwx,o-rwx,u+X /etc/skel.ipa/ "${USER_HOME}"; then
        echo "ERROR::${FUNCNAME} ${USERNAME}: cannot copy /etc/skel.ipa in ${USER_HOME}"
        return 1
    fi
    if ! find /etc/skel.ipa -printf "${USER_HOME}/%P\n" | restorecon -f -; then
        echo "ERROR::${FUNCNAME} ${USERNAME}: could not restore SELinux security context of ${USER_HOME}"
        return 1
    fi
    echo ${SUCCESS_LOG}
}

mkscratch () {
    local USERNAME=$1
    local MANAGE_HOME_DIR="${MANAGE_HOME_DIR:-true}"

    if [ -z "${USERNAME}" ]; then
        echo "ERROR::${FUNCNAME}: username unspecified"
        return 3
    fi

    local USER_UID USER_GID USER_HOME
    if ! get_user_info "${USERNAME}"; then
        echo "ERROR::${FUNCNAME} ${USERNAME}: could not retrieve user attributes from LDAP"
        return 1
    fi

    if [[ ! "${USER_UID}" =~ ^[0-9]+$ ]]; then
        echo "ERROR::${FUNCNAME} ${USERNAME}: UID not defined or invalid in LDAP"
        return 1
    fi

    if [[ ! "${USER_GID}" =~ ^[0-9]+$ ]]; then
        echo "ERROR::${FUNCNAME} ${USERNAME}: GID not defined or invalid in LDAP"
        return 1
    fi

    if [ -z "${USER_HOME}" ]; then
        echo "ERROR::${FUNCNAME} ${USERNAME}: home path not defined in LDAP"
        return 1
    fi

    local USER_SCRATCH="/scratch/${USERNAME}"
    if [[ ! -d "${USER_SCRATCH}" ]]; then
        mkdir -Z -m 750 -p ${USER_SCRATCH} || return 1
    fi
    if [ "${MANAGE_HOME_DIR}" == "true" ]; then
        ln -sfT ${USER_SCRATCH} "${USER_HOME}/scratch" || return 1
        chown -h ${USER_UID}:${USER_GID} "${USER_HOME}/scratch" || return 1
    fi
    if [ -O "${USER_SCRATCH}" ]; then
        chown ${USER_UID}:${USER_GID} ${USER_SCRATCH} || return 1
    fi
    echo "INFO::${FUNCNAME} ${USERNAME}: scratch configured"
    return 0
}

mkproject() {
    local GROUP=$1
    local MANAGE_PROJECT_DIR="${MANAGE_PROJECT_DIR:-true}"
    local PROJECT_GROUP="/project/$GROUP"

    if [ -z "${GROUP}" ]; then
        echo "ERROR::${FUNCNAME}: group unspecified"
        return 3
    fi

    if [ -z "${BASEDN}" ]; then
        local BASEDN=$(grep -o -P "basedn = \K(.*)" /etc/ipa/default.conf)
    fi

    # Retrieve the group object class and numeric GID directly from LDAP.
    local GROUP_INFO
    if ! GROUP_INFO=$(ldapsearch -Y EXTERNAL -H "${LDAP_URI}" -Q -o ldif-wrap=no -LLL -s base \
        -b "cn=${GROUP},cn=groups,cn=accounts,${BASEDN}" objectClass gidNumber); then
        echo "ERROR::${FUNCNAME} ${GROUP}: error while searching for group name in LDAP"
        return 1
    fi

    # If group is not posix, we disable folder creation.
    if ! echo "${GROUP_INFO}" | grep -q "objectClass: posixgroup"; then
        MANAGE_PROJECT_DIR="false"
    fi

    # Function is called with the intent to create folders under /project
    if [[ "${MANAGE_PROJECT_DIR}" == "true" ]]; then
        local GID
        GID=$(sed -n 's/^gidNumber: //p' <<< "${GROUP_INFO}")
        if [[ ! "${GID}" =~ ^[0-9]+$ ]]; then
            echo "ERROR::${FUNCNAME} ${GROUP}: GID not defined or invalid in LDAP"
            return 1
        fi

        local PROJECT_GID="/project/$GID"
        if [ ! -d ${PROJECT_GID} ]; then
            # SELinux labeling is best-effort: mkdir -Z may warn about labeling
            # failures while returning success. We accept this across the provisioning
            # functions and do not run recursive restorecon, to avoid relabeling
            # existing user content. Directory-creation failures still require a retry.
            mkdir -Z -m 2770 -p ${PROJECT_GID} || return 1
        fi
        local PROJECT_OWNER_GID
        PROJECT_OWNER_GID=$(stat -c '%g' -- "${PROJECT_GID}") || return 1
        if [[ "${PROJECT_OWNER_GID}" == "0" ]]; then
            chown "root:${GID}" "${PROJECT_GID}" || return 1
        fi
        ln -sfT "/project/$GID" ${PROJECT_GROUP} || return 1
        restorecon -F ${PROJECT_GROUP} || return 1

        echo "INFO::${FUNCNAME} ${GROUP}: ${PROJECT_GID} configured"
    fi

    # We create the associated account in slurm
    if sacctmgr_output=$(/opt/software/slurm/bin/sacctmgr add account $GROUP -i 2>&1); then
        echo "INFO::${FUNCNAME} ${GROUP}: SlurmDB account created"
    elif [[ "${sacctmgr_output}" == *"Already existing account ${GROUP}"* ]]; then
        echo "WARN::${FUNCNAME} ${GROUP}: SlurmDB account already exists"
    else
        echo "ERROR::${FUNCNAME} ${GROUP}: could not create SlurmDB account:"
        echo "${sacctmgr_output}" | sed 's/^/\t/'
        return 1
    fi

    return 0
}

# Coalesce group reconciliation requests, including requests from mkhome.
# pending covers queued/running/retrying work; dirty requests another snapshot.
queue_modproject() {
    local group=$1 pipe=$2
    local sync_dir="${MKHOME_PROJECT_DIR}/project_sync"
    mkdir -p "${sync_dir}" || return 1
    touch "${sync_dir}/${group}.dirty" || return 1
    if mkdir "${sync_dir}/${group}.pending" 2> /dev/null; then
        (echo modproject 0 "${group}" > "${pipe}") &
    fi
}

# return codes
# 0: project was correctly modified
# 1: context did not allow function to execute, retry later
# 2: not used
# 3: invalid arguments, do not retry
modproject() {
    local GROUP=$1
    local MANAGE_HOME_DIR="${MANAGE_HOME_DIR:-true}"
    local MANAGE_PROJECT_DIR="${MANAGE_PROJECT_DIR:-true}"
    local USERNAMES

    if [ -z "${GROUP}" ]; then
        echo "ERROR::${FUNCNAME}: group unspecified"
        return 3
    fi

    local PROJECT_GROUP="/project/$GROUP"

    if [ -z "${BASEDN}" ]; then
        local BASEDN=$(grep -o -P "basedn = \K(.*)" /etc/ipa/default.conf)
    fi

    # Retrieve the group information that are only available in LDAP:
    # - does the group exist?
    # - is it a posix group (objectClass: posixgroup)?
    local GROUP_INFO
    if ! GROUP_INFO=$(ldapsearch -Y EXTERNAL -H "${LDAP_URI}" -Q -o ldif-wrap=no -LLL -s base -b "cn=${GROUP},cn=groups,cn=accounts,${BASEDN}" "objectClass"); then
        echo "ERROR::${FUNCNAME} ${GROUP}: error while searching for group name in LDAP"
        return 1
    fi

    if [[ -z "${GROUP_INFO}" ]]; then
        echo "ERROR::${FUNCNAME} ${GROUP}: group not found in LDAP"
        return 3
    fi

    # If group is not posix, we disable folder creation.
    if ! echo "${GROUP_INFO}" | grep -q "objectClass: posixgroup"; then
        MANAGE_PROJECT_DIR="false"
    fi

    if [[ "${MANAGE_PROJECT_DIR}" == "true" ]]; then
        local GROUP_LINK=$(readlink /project/${GROUP})
        if [[ -z "${GROUP_LINK}" ]]; then
            echo "ERROR::${FUNCNAME}: $GROUP $USERNAMES mkproject has yet been ran for this group"
            return 1
        fi
    else
        if [[ $(/opt/software/slurm/bin/sacctmgr -n list account Name=${GROUP} | wc -l) -eq 0 ]]; then
            echo "ERROR::${FUNCNAME}: Slurm account "${GROUP}" does not exist"
            return 1
        fi
    fi
    # Use one authoritative snapshot for both additions and removals. IPA
    # expands indirect membership; LDAP access-log searches are not membership.
    local GROUP_MEMBERS SLURM_MEMBERS MISSING_MEMBERS OBSOLETE_MEMBERS
    if ! GROUP_MEMBERS=$(kexec ipa group-show "${GROUP}" --raw); then
        echo "ERROR::${FUNCNAME} ${GROUP}: could not retrieve IPA membership"
        return 1
    fi
    GROUP_MEMBERS=$(echo "${GROUP_MEMBERS}" |
        grep -Ei '^[[:space:]]*(member|memberindirect):' |
        grep -oP 'uid=\K[^,]+(?=,cn=users,cn=accounts,)' | LC_ALL=C sort -u)
    if ! SLURM_MEMBERS=$(/opt/software/slurm/bin/sacctmgr list assoc account="${GROUP}" format=user --noheader -P); then
        echo "ERROR::${FUNCNAME} ${GROUP}: could not retrieve Slurm membership"
        return 1
    fi
    SLURM_MEMBERS=$(echo "${SLURM_MEMBERS}" | awk NF | LC_ALL=C sort -u)
    MISSING_MEMBERS=$(LC_ALL=C comm -23 <(printf '%s\n' "${GROUP_MEMBERS}" | awk NF) <(printf '%s\n' "${SLURM_MEMBERS}" | awk NF))
    OBSOLETE_MEMBERS=$(LC_ALL=C comm -13 <(printf '%s\n' "${GROUP_MEMBERS}" | awk NF) <(printf '%s\n' "${SLURM_MEMBERS}" | awk NF))

    # Revoke obsolete associations before adding new ones.
    USERNAMES=${OBSOLETE_MEMBERS}
    if [[ -n "${USERNAMES}" ]]; then
        delproject "${GROUP}" "${USERNAMES}" || return 1
    fi

    # Ensure folders also exist for users already associated with Slurm.
    USERNAMES=${GROUP_MEMBERS}
    if [[ -n "${USERNAMES}" ]]; then
        if [[ "${MANAGE_PROJECT_DIR}" == "true" ]]; then
            for USERNAME in $USERNAMES; do
                local USER_UID USER_GID USER_HOME
                if ! get_user_info "${USERNAME}"; then
                    echo "ERROR::${FUNCNAME} ${GROUP} ${USERNAME}: could not retrieve user attributes from LDAP"
                    return 1
                fi

                if [[ ! "${USER_UID}" =~ ^[0-9]+$ ]]; then
                    echo "ERROR::${FUNCNAME} ${USERNAME}: UID not defined or invalid in LDAP"
                    return 1
                fi

                local PROJECT_CHANGED=false
                if [[ "${MANAGE_HOME_DIR}" == "true" ]]; then
                    if [[ ! "${USER_GID}" =~ ^[0-9]+$ ]]; then
                        echo "ERROR::${FUNCNAME} ${USERNAME}: GID not defined or invalid in LDAP"
                        return 1
                    fi

                    if [ -z "${USER_HOME}" ]; then
                        echo "ERROR::${FUNCNAME} ${USERNAME}: home path not defined in LDAP"
                        return 1
                    fi

                    if [ ! -d "${USER_HOME}/projects" ]; then
                        mkdir -m 0755 -Z -p "${USER_HOME}/projects" || return 1
                        PROJECT_CHANGED=true
                    fi
                    local PROJECTS_OWNER_GID
                    PROJECTS_OWNER_GID=$(stat -c '%g' -- "${USER_HOME}/projects") || return 1
                    if [[ "${PROJECTS_OWNER_GID}" == "0" && "${USER_GID}" != "0" ]]; then
                        chgrp "${USER_GID}" "${USER_HOME}/projects" || return 1
                        PROJECT_CHANGED=true
                    fi

                    local PROJECT_LINK="${USER_HOME}/projects/${GROUP}"
                    if [[ ! -L "${PROJECT_LINK}" || "$(readlink -- "${PROJECT_LINK}")" != "${PROJECT_GROUP}" ]]; then
                        ln -sfT "${PROJECT_GROUP}" "${PROJECT_LINK}" || return 1
                        PROJECT_CHANGED=true
                    fi
                fi

                local PROJECT_USER="${PROJECT_GROUP}/${USERNAME}"
                if [ ! -d "${PROJECT_USER}" ]; then
                    mkdir -Z -m 2700 ${PROJECT_USER} || return 1
                    PROJECT_CHANGED=true
                fi
                if [ -O "${PROJECT_USER}" ] && [[ "${USER_UID}" != "0" ]]; then
                    chown "${USER_UID}" "${PROJECT_USER}" || return 1
                    PROJECT_CHANGED=true
                fi
                if [[ "${PROJECT_CHANGED}" == "true" ]]; then
                    echo "INFO::${FUNCNAME} ${GROUP} ${USERNAME}: ${PROJECT_USER} configured"
                fi
            done
        fi
    fi
    USERNAMES=${MISSING_MEMBERS}
    if [[ -n "${USERNAMES}" ]]; then
        if sacctmgr_output=$(/opt/software/slurm/bin/sacctmgr add user ${USERNAMES} Account=${GROUP} -i 2>&1); then
            echo "INFO::${FUNCNAME} ${GROUP}: ${USERNAMES//[$'\n']/ } added to ${GROUP} in SlurmDB"
        elif [[ "${sacctmgr_output}" == *"Request didn't affect anything"*"Nothing added"* ]]; then
            echo "WARN::${FUNCNAME} ${GROUP} ${USERNAMES//[$'\n']/ }: already added to SlurmDB account"
        else
            echo "ERROR::${FUNCNAME} ${GROUP}: could not add ${USERNAMES//[$'\n']/ } added to ${GROUP}"
            echo "${sacctmgr_output}" | sed 's/^/\t/'
            return 1
        fi
    fi
    return 0
}

delproject() {
    # Remove users from a group, if no users is provided in argument
    # every users from that group in SlurmDB are removed.
    local GROUP=$1
    local USERNAMES=$2
    local MANAGE_HOME_DIR="${MANAGE_HOME_DIR:-true}"
    local MANAGE_PROJECT_DIR="${MANAGE_PROJECT_DIR:-true}"

    local PROJECT_GROUP="/project/$GROUP"
    # If group folder does not exist, we disable folder and symlinks removal.
    if [ ! -L "${PROJECT_GROUP}" ]; then
        MANAGE_PROJECT_DIR="false"
    fi

    if [[ -z "${USERNAMES}" ]]; then
        if USERNAMES=$(/opt/software/slurm/bin/sacctmgr list assoc account=$GROUP format=user --noheader -P); then
            USERNAMES=$(echo "${USERNAMES}" | awk NF | sort)
        else
            echo "ERROR::${FUNCNAME}: failure while querying ${GROUP} in SlurmDB"
            return 1
        fi
    fi
    if [[ ! -z "$USERNAMES" ]]; then
        if [[ "${MANAGE_PROJECT_DIR}" == "true" && "${MANAGE_HOME_DIR}" == "true" ]]; then
            local USER_UID USER_GID USER_HOME
            for USERNAME in $USERNAMES; do
                get_user_info "${USERNAME}"
                local LDAP_OUTPUT=$?
                if [[ "${LDAP_OUTPUT}" -eq 32 ]]; then
                    # LDAP noSuchObject: the user was already deleted.
                    echo "WARN::${FUNCNAME} ${GROUP} ${USERNAME}: user not found in LDAP - skipping home symlink cleanup"
                    continue
                elif [[ ! "${LDAP_OUTPUT}" -eq 0 ]]; then
                    echo "ERROR::${FUNCNAME} ${GROUP} ${USERNAME}: could not retrieve user attributes from LDAP"
                    return 1
                fi

                if [ -z "${USER_HOME}" ]; then
                    echo "ERROR::${FUNCNAME} ${GROUP} ${USERNAME}: home path not defined in LDAP"
                    return 1
                fi
                if [ ! -L "${USER_HOME}/projects/$GROUP" ]; then
                    echo "WARN::${FUNCNAME} ${GROUP}: symlink ${USER_HOME}/projects/$GROUP does not exist"
                    continue
                fi
                local RM_OUTPUT
                if RM_OUTPUT=$(rm "${USER_HOME}/projects/$GROUP" 2>&1); then
                    echo "INFO::${FUNCNAME} ${GROUP}: removed symlink $USER_HOME/projects/$GROUP"
                else
                    echo "ERROR::${FUNCNAME} ${GROUP}: could not remove symlink $USER_HOME/projects/$GROUP"
                    echo "\t${RM_OUTPUT}"
                    return 1
                fi
            done
        fi
        if sacctmgr_output=$(/opt/software/slurm/bin/sacctmgr remove user $USERNAMES Account=${GROUP} -i 2>&1); then
            echo "INFO::${FUNCNAME}: removed ${USERNAMES} from ${GROUP} in SlurmDB"
        elif [[ "${sacctmgr_output}" == *"Nothing deleted"* ]]; then
            echo "WARN::${FUNCNAME} ${GROUP} ${USERNAMES}: nothing deleted from SlurmDB"
        else
            echo "ERROR::${FUNCNAME}: could not remove ${USERNAME} from ${GROUP} in SlurmDB"
            echo "${sacctmgr_output}" | sed 's/^/\t/'
            return 1
        fi
    fi
    return 0
}
