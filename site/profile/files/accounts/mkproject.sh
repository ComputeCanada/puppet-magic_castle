#!/bin/bash

# mkproject.sh watches 389-ds access log for operations related to group
# matching a regex ($PROJECT_REGEX) with the intent of automatically
# manipulating Slurm accounts and folders under /project associated with these
# groups.

# Each ADD/MOD/DEL must have its own successful RESULT before it is queued.
# ADD creates the project; MOD reconciles its complete IPA membership with
# Slurm; DEL removes its Slurm associations. All actions share one consumer.
#
# Access-log user searches are not used to infer membership. A reconciliation
# uses one IPA snapshot (direct and indirect users) for additions and removals.
# Pending MODs are coalesced by group. Updates received during reconciliation
# mark the group dirty and cause another pass, so later changes converge too.

BASEDN=$(grep -o -P "basedn = \K(.*)" /etc/ipa/default.conf)
LDAP_URI=$(grep -o -P "ldap_uri = \K(.*)" /etc/ipa/default.conf)

source /sbin/account_functions.sh

mkdir -p ${MKHOME_PROJECT_DIR}

update_mkproject_cache () {
    flock ${MKPROJECT_CACHE_LOCK} -c "echo ${1} >> ${MKPROJECT_CACHE} && (test \$(wc -l < ${MKPROJECT_CACHE}) -le ${MKPROJECT_CACHE_SIZE} || sed -i '1d' ${MKPROJECT_CACHE})"
}

remove_from_mkproject_cache () (
    flock -x 9 || return 1
    local temporary_cache result
    temporary_cache=$(mktemp "${MKPROJECT_CACHE}.XXXXXX") || return 1
    grep -Fxv -- "${1}" "${MKPROJECT_CACHE}" > "${temporary_cache}"
    result=$?
    if [[ ${result} -gt 1 ]]; then
        rm -f "${temporary_cache}"
        return "${result}"
    fi
    mv -f "${temporary_cache}" "${MKPROJECT_CACHE}"
) 9> "${MKPROJECT_CACHE_LOCK}"

LAST_TIMESTAMP_FILE=${MKHOME_PROJECT_DIR}/mkproject.last_timestamp

# FIFO pipes could eventually be replaced by sockets
# to allow input from other instances, like login nodes
# and avoid background echo processes. A FIFO pipe can
# be replaced by a UNIX socket with netcat and this command:
#   nc -lkU /var/tmp/dsocket
# To write data to the UNIX socket:
#   echo "${ACTION}" $((NRETRY+1)) "${GROUP}" | nc -N -U /var/tmp/dsocket

trap "rm -f ${MODPROJECT_PIPE} ${MODPROJECT_RETRY_PIPE} ${MKPROJECT_CACHE}" EXIT

if [[ ! -p ${MODPROJECT_PIPE} ]]; then
    mkfifo -m=600 ${MODPROJECT_PIPE}
fi

if [[ ! -p ${MODPROJECT_RETRY_PIPE} ]]; then
    mkfifo -m=600 ${MODPROJECT_RETRY_PIPE}
fi

# Create an empty cache file that is only r+w by root
install -m 600 /dev/null ${MKPROJECT_CACHE}

wait_for_slurm

queue_action () {
    local action=$1
    local nretry=$2
    local group=$3
    if [[ ${nretry} -gt "${MAX_RETRIES}" ]]; then
        echo "ERROR::${action} ${group}: retry limit reached"
        return 1
    fi
    # Wait outside the consumer so fresh requests can continue processing.
    (
        if [[ ${2} -gt 0 ]]; then
            sleep "${RETRY_DELAY}"
            echo "${@}" > "${MODPROJECT_RETRY_PIPE}"
        else
            echo "${@}" > "${MODPROJECT_PIPE}"
        fi
    ) &
}

PROJECT_SYNC_DIR="${MKHOME_PROJECT_DIR}/project_sync"
mkdir -p "${PROJECT_SYNC_DIR}"
# Recover requests whose FIFO entry or running worker was lost on restart.
for PENDING in "${PROJECT_SYNC_DIR}"/*.pending; do
    [[ -d "${PENDING}" ]] || continue
    touch "${PENDING%.pending}.dirty"
    rmdir "${PENDING}"
done
for DIRTY in "${PROJECT_SYNC_DIR}"/*.dirty; do
    [[ -f "${DIRTY}" ]] || continue
    GROUP=${DIRTY##*/}
    queue_modproject "${GROUP%.dirty}" "${MODPROJECT_PIPE}"
done

finish_modproject () {
    local group=$1
    # Release before checking dirty: a concurrent producer either leaves a
    # dirty flag for us or claims pending itself and queues the next pass.
    rmdir "${PROJECT_SYNC_DIR}/${group}.pending"
    if [[ -f "${PROJECT_SYNC_DIR}/${group}.dirty" ]]; then
        queue_modproject "${group}" "${MODPROJECT_PIPE}"
    fi
}

# Loop over three sources of project modification
# 1. Modification coming from SLAPD log
# 2. Modification coming from mkhome daemon
# 3. Modification coming from the loop that have errored on a previous try.
(
    tail -n+1 -F ${MODPROJECT_PIPE} &
    tail -n+1 -F ${MODPROJECT_RETRY_PIPE} &
    tail -n+1 -F ${MKHOME_MODPROJECT_PIPE}
) |
# Queue format: ACTION NRETRY GROUP.
while read -r ACTION NRETRY GROUP; do
    case "${ACTION}" in
        mkproject)
            # Duplicate creation retries retain their action after success.
            if grep -Fxq "${GROUP}" "${MKPROJECT_CACHE}"; then
                continue
            fi
            if mkproject "${GROUP}"; then
                update_mkproject_cache "${GROUP}"
                queue_modproject "${GROUP}" "${MODPROJECT_PIPE}"
            else
                queue_action mkproject $((NRETRY+1)) "${GROUP}"
            fi
            ;;
        modproject)
            # Requests arriving after this point require another snapshot.
            rm -f "${PROJECT_SYNC_DIR}/${GROUP}.dirty"
            modproject "${GROUP}"
            RESULT=$?
            if [[ "${RESULT}" -eq 1 ]] && queue_action modproject $((NRETRY+1)) "${GROUP}"; then
                continue
            fi
            finish_modproject "${GROUP}"
            ;;
        delproject)
            if [[ "${NRETRY}" -eq 0 ]]; then
                remove_from_mkproject_cache "${GROUP}"
            fi
            if ! delproject "${GROUP}"; then
                queue_action delproject $((NRETRY+1)) "${GROUP}"
            fi
            ;;
        *)
            echo "ERROR::mkproject queue: unknown action ${ACTION}"
            ;;
    esac
done &

# Do not reprocess previous entries if we remember the last timestamp treated
if [ -e ${LAST_TIMESTAMP_FILE} ]; then
    LAST_TIMESTAMP=$(cat ${LAST_TIMESTAMP_FILE})
    if [ "${LAST_TIMESTAMP}" != "" ]; then
        # We don't expect more than one line matching the timestamp but if
        # it happens, we will replay from the first match.
        start_index=$(grep -m 1 -n -F "${LAST_TIMESTAMP}" ${SLAPD_LOG_FILE} | cut -d: -f1)
        start_index=$(($start_index+1))
    else
        start_index=1
    fi
else
    start_index=1
fi

tail -n +${start_index} -F ${SLAPD_LOG_FILE} |
grep --line-buffered -P " (ADD|DEL|MOD) dn=\"cn=${PROJECT_REGEX},cn=groups" |
sed -n -u -r 's/^\[(.*) [-+][0-9]{4}\] conn=([0-9]*) op=([0-9]*) (ADD|DEL|MOD) dn="cn=(.*),cn=groups.*$/\1 \2 \3 \4 \5/p' |
while read TIMESTAMP CONN OP_ID OP GROUP; do
    # We only treat successful operations.
    if wait_for_result "${CONN}" "${OP_ID}" "${TIMESTAMP}"; then
        # We support three operations : ADD, MOD or DEL
        case ${OP} in
            ADD)
                queue_action mkproject 0 "${GROUP}"
                ;;
            MOD)
                queue_modproject "${GROUP}" "${MODPROJECT_PIPE}"
                ;;
            DEL)
                queue_action delproject 0 "${GROUP}"
                ;;
            *)
                echo "Unknown operation ${OP}"
                ;;
        esac
    fi
    echo "${TIMESTAMP}" > ${LAST_TIMESTAMP_FILE}
done
