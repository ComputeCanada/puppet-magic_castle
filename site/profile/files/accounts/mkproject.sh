#!/bin/bash

BASEDN="$(grep -oP 'basedn = \K(.*)' /etc/ipa/default.conf)"

declare -A group_memory_users

PROJECT_PREFIX="ctb|def|rpp|rrg"

tail -F /var/log/dirsrv/slapd-*/access |
grep --line-buffered -P "MOD dn=\"cn=\K((${PROJECT_PREFIX})-[a-z0-9A-Z_-]*)(?=,cn=groups)" |
while read LINE; do
    GROUP=$(echo $LINE | grep -oP "MOD dn=\"cn=\K((${PROJECT_PREFIX})-[a-z0-9A-Z_-]*)(?=,cn=groups)")
    USERNAME=$(grep -B 5 -F "$LINE" /var/log/dirsrv/slapd-*/access | grep -oP "SRCH base=\"uid=\K([a-z0-9A-Z_-]*)(?=,cn=users)")

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

    if [[ -z "$USERNAME" ]]; then
        continue
    fi

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

    /opt/software/slurm/bin/sacctmgr add user ${USERNAME} Account=${GROUP} -i

done