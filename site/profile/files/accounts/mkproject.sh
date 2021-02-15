#!/bin/bash

BASEDN="$(grep -oP 'basedn = \K(.*)' /etc/ipa/default.conf)"
export KRB5CCNAME="/root/mkprojectdaemon.krb5"

declare -A group_memory_calls
declare -A group_memory_users

PROJECT_PREFIX="ctb|def|rpp|rrg"

tail -F /var/log/dirsrv/slapd-*/access |
grep --line-buffered -oP "MOD dn=\"cn=\K((${PROJECT_PREFIX})-[a-z0-9A-Z_-]*)(?=,cn=groups)" |
while read GROUP; do
    if [[ -z ${group_memory_calls[$GROUP]} ]]; then
        group_memory_calls[$GROUP]=1
    else
        group_memory_calls[$GROUP]=$((${group_memory_calls[$GROUP]}+1))
    fi

    if [[ -z ${group_memory_users[$GROUP]} ]]; then
        group_memory_users[$GROUP]=0
        /opt/software/slurm/bin/sacctmgr add account $GROUP -i Description='Cloud Cluster Account' Organization='Compute Canada'
        if [[ ! -d /project/$GROUP ]]; then
            GID=$(getent group $GROUP | cut -d: -f3)
            mkdir -p "/project/$GID"
            chown root:"$GROUP" "/project/$GID"
            chmod 2770 "/project/$GID"
            ln -sfT "/project/$GID" "/project/$GROUP"
            restorecon -F -R /project/$GID /project/$GROUP
        fi
    fi

    # Skip ldapsearch if we have already processed more usernames than the number of lines found so far in log
    if [[ ${group_memory_users[$GROUP]} -ge ${group_memory_calls[$GROUP]} ]]; then
        continue
    fi

    kinit -k -t /etc/mokey/keytab/mokeyapp.keytab mokeyapp
    USERNAMES=$(ldapsearch -Q -s one -b "cn=users,cn=accounts,${BASEDN}" "memberOf=*${GROUP}*" uid | grep -oP 'uid: \K(.*)' | tail -n +$((${group_memory_users[$GROUP]}+1)))
    kdestroy

    if [[ -z "$USERNAMES" ]]; then
        continue
    fi

    for USERNAME in $USERNAMES; do
        USER_HOME="/mnt/home/$USERNAME"

        PRO_USER="/project/$GROUP/$USERNAME"
        mkdir -p $PRO_USER
        mkdir -p "$USER_HOME/projects"
        ln -sfT "/project/$GROUP" "$USER_HOME/projects/$GROUP"

        chgrp $USERNAME "$USER_HOME/projects"
        chown $USERNAME $PRO_USER
        chmod 0755 "$USER_HOME/projects"
        chmod 2700 $PRO_USER
        restorecon -F -R /project/$GROUP/$USERNAME
        group_memory_users[$GROUP]=$((${group_memory_users[$GROUP]}+1))
    done

    /opt/software/slurm/bin/sacctmgr add user ${USERNAMES[@]} Account=${GROUP} -i

done