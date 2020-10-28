#!/bin/bash

BASEDN="$(grep -oP 'basedn = \K(.*)' /etc/ipa/default.conf)"

declare -A group_memory

tail -f /var/log/dirsrv/slapd-*/access |
grep --line-buffered -oP 'MOD dn=\"cn=\K(def-[a-z0-9A-Z_-]*)(?=,cn=groups)' |
while read GROUP; do

    if [[ -z ${group_memory[$GROUP]} ]]; then
        group_memory[$GROUP]=1
        if [[ ! -d /project/$GROUP ]]; then
            GID=$(getent group $GROUP | cut -d: -f3)
            mkdir -p "/project/$GID"
            chown root:"$GROUP" "/project/$GID"
            chmod 2770 "/project/$GID"
            ln -sfT "/project/$GID" "/project/$GROUP"
            restorecon -F -R /project/$GROUP
        fi
    fi

    kinit -k -t /etc/mokey/keytab/mokeyapp.keytab mokeyapp
    USERNAMES=$(ldapsearch -Q -s one -b "cn=users,cn=accounts,${BASEDN}" "memberOf=*${GROUP}*" uid | grep -oP 'uid: \K(.*)' | tail -n +${group_memory[$GROUP]})
    kdestroy

    for USERNAME in $USERNAME; do
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
        group_memory[$GROUP]=$((${group_memory[$GROUP]}+1))
    done

done