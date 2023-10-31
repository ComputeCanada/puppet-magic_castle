#!/bin/bash

wait_id () {
    local USERNAME=$1
    local FOUND=0
    for i in $(seq 1 12); do
        if ! SSS_NSS_USE_MEMCACHE=no id $USERNAME &> /dev/null; then
            sleep 5
        else
            FOUND=1
            break
        fi
    done
    if [ $FOUND -eq 0 ]; then
        systemctl restart sssd
        sleep 5
        id $USERNAME &> /dev/null
        return $?
    fi
    return 0
}

mkhome () {
    local USERNAME=$1

    wait_id $USERNAME

    if [ ! $? -eq 0 ]; then
        echo "ERROR - ${USERNAME} is not showing up in SSSD after 1min - cannot make its home."
        return 1
    fi

    local USER_HOME=$(SSS_NSS_USE_MEMCACHE=no getent passwd $USERNAME | cut -d: -f6)
    local MNT_USER_HOME="/mnt${USER_HOME}"
    local RSYNC_DONE=0
    for i in $(seq 1 5); do
        rsync -opg -r -u --chown=$USERNAME:$USERNAME --chmod=Dg-rwx,o-rwx,Fg-rwx,o-rwx,u+X /etc/skel.ipa/ ${MNT_USER_HOME}
        if [ $? -eq 0 ]; then
            RSYNC_DONE=1
            break
        else
            sleep 5
        fi
    done
    if [ ! $RSYNC_DONE -eq 1 ]; then
        echo "ERROR - Could not rsync /etc/skel.ipa in ${MNT_USER_HOME}"
        return 1
    else
        echo "SUCCESS - ${USERNAME} home initialized in ${MNT_USER_HOME}"
    fi
    restorecon -F -R ${MNT_USER_HOME}
}

mkscratch () {
    local USERNAME=$1
    local WITH_HOME=$2

    wait_id $USERNAME

    if [ ! $? -eq 0 ]; then
        echo "$USERNAME is not showing up in SSSD after 1min - cannot make its scratch."
        return 1
    fi

    local USER_SCRATCH="/scratch/${USERNAME}"
    local MNT_USER_SCRATCH="/mnt/${USER_SCRATCH}"
    if [[ ! -d "${MNT_USER_SCRATCH}" ]]; then
        mkdir -p ${MNT_USER_SCRATCH}
        if [ "$WITH_HOME" == "true" ]; then
            local USER_HOME=$(SSS_NSS_USE_MEMCACHE=no getent passwd $USERNAME | cut -d: -f6)
            local MNT_USER_HOME="/mnt${USER_HOME}"
            ln -sfT ${USER_SCRATCH} "${MNT_USER_HOME}/scratch"
            chown -h ${USERNAME}:${USERNAME} "${MNT_USER_HOME}/scratch"
        fi
        chown -h ${USERNAME}:${USERNAME} ${MNT_USER_SCRATCH}
        chmod 750 ${MNT_USER_SCRATCH}
        restorecon -F -R ${MNT_USER_SCRATCH}
        echo "SUCCESS - ${USERNAME} scratch initialized in ${MNT_USER_SCRATCH}"
    fi
}

mkproject() {
    local GROUP=$1
    local WITH_FOLDER=$2
    # A new group has been created
    # We create the associated account in slurm
    /opt/software/slurm/bin/sacctmgr add account $GROUP -i
    if [ "$WITH_FOLDER" == "true" ]; then
        # We ignore the SSSD cache before recovering the group GID.
        # Using the cache would be problematic if the group existed before with a different gid.
        GID=""
        while [ -z "$GID" ]; do
            sleep 5
            GID=$(SSS_NSS_USE_MEMCACHE=no getent group $GROUP | cut -d: -f3)
        done

        # Then we create the project folder
        MNT_PROJECT_GID="/mnt/project/$GID"
        MNT_PROJECT_GROUP="/mnt/project/$GROUP"
        mkdir -p ${MNT_PROJECT_GID}
        chown root:"$GROUP" ${MNT_PROJECT_GID}
        chmod 2770 ${MNT_PROJECT_GID}
        ln -sfT "/project/$GID" ${MNT_PROJECT_GROUP}
        restorecon -F -R ${MNT_PROJECT_GID} ${MNT_PROJECT_GROUP}
    fi
}

modproject() {
    local GROUP=$1
    local WITH_FOLDER=$2
    local USERNAMES="${@:3}"

    # The operation that add users to a group would have operations with a uid.
    # If we found none, $USERNAMES will be empty, and it means we don't have
    # anything to add to Slurm and /project
    if [[ ! -z "${USERNAMES}" ]]; then
        local MNT_PROJECT="/mnt$(readlink /mnt/project/${GROUP})"
        if [ "$WITH_FOLDER" == "true" ]; then
            for USERNAME in $USERNAMES; do
                wait_id $USERNAME

                if [ ! $? -eq 0 ]; then
                    echo "$USERNAME is not showing up in SSSD after 1min - cannot make its project."
                    continue
                fi

                local USER_HOME="/mnt/home/${USERNAME}"

                local PRO_USER="${MNT_PROJECT}/${USERNAME}"
                mkdir -p ${PRO_USER}
                mkdir -p "${USER_HOME}/projects"
                ln -sfT "/project/${GROUP}" "${USER_HOME}/projects/${GROUP}"

                chgrp "${USERNAME}" "${USER_HOME}/projects"
                chown "${USERNAME}" "${PRO_USER}"
                chmod 0755 "${USER_HOME}/projects"
                chmod 2700 "${PRO_USER}"
                restorecon -F -R "${MNT_PROJECT}/${USERNAME}"
            done
        fi
        /opt/software/slurm/bin/sacctmgr add user ${USERNAMES} Account=${GROUP} -i
    else
        # If group has been modified but no uid were found in the log, it means
        # user(s) have been removed from the groups.
        # We identify which ones by comparing Slurm account with group.
        sss_cache -g$GROUP
        local USER_GROUP=$(sleep 5 && SSS_NSS_USE_MEMCACHE=no getent group $GROUP | cut -d: -f4 | tr "," "\n" | sort)
        local SLURM_ACCOUNT=$(/opt/software/slurm/bin/sacctmgr list assoc account=$GROUP format=user --noheader -p | cut -d'|' -f1 | awk NF | sort)
        local USERNAMES=$(comm -2 -3 <(echo "$SLURM_ACCOUNT") <(echo "$USER_GROUP"))
        if [[ ! -z "$USERNAMES" ]]; then
            /opt/software/slurm/bin/sacctmgr remove user $USERNAMES Account=${GROUP} -i
            if [ "$WITH_FOLDER" == "true" ]; then
                for USERNAME in $USERNAMES; do
                    local USER_HOME="/mnt/home/$USERNAME"
                    rm "$USER_HOME/projects/$GROUP"
                done
            fi
        fi
    fi
}

delproject() {
    local GROUP=$1
    local WITH_FOLDER=$2

    # A group has been removed.
    # Since we do not want to delete any data we only remove the
    # symlinks and remove the users from the slurm account.
    local USERNAMES=$(/opt/software/slurm/bin/sacctmgr list assoc account=$GROUP format=user --noheader -p | cut -d'|' -f1 | awk NF | sort)
    if [[ ! -z "$USERNAMES" ]]; then
        /opt/software/slurm/bin/sacctmgr remove user $USERNAMES Account=${GROUP} -i
        if [ "$WITH_FOLDER" == "true" ]; then
            for USERNAME in $USERNAMES; do
                USER_HOME="/mnt/home/$USERNAME"
                rm "$USER_HOME/projects/$GROUP"
            done
        fi
    fi
}