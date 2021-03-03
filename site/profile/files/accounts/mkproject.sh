#!/bin/bash

PROJECT_PREFIX="ctb|def|rpp|rrg"
PREV_CONN=""

tail -F /var/log/dirsrv/slapd-*/access |
grep --line-buffered -P "dn=\"cn=(${PROJECT_PREFIX})-[a-z0-9A-Z_-]*,cn=groups" |
sed -u -r 's/^.*conn=([0-9]*) op=[0-9]* (\w+) dn="cn=(.*),cn=groups.*$/\1 \2 \3/' |
while read CONN OP GROUP; do
    # An operation has been done on a group in LDAP
    # We have already completed this request
    if [[ "$PREV_CONN" == "$CONN" ]]; then
        continue
    fi

    # We wait for the operation $CONN to be completed
    while ! grep -q "$CONN op=[0-9]* UNBIND" /var/log/dirsrv/slapd-*/access; do
        sleep 1;
    done

    # We support three operations : ADD, MOD or DEL
    if [[ "$OP" == "ADD" ]]; then
        # A new group has been created
        # We create the associated account in slurm
        /opt/software/slurm/bin/sacctmgr add account $GROUP -i

        # Then we create the project folder
        GID=$(getent group $GROUP | cut -d: -f3)
        mkdir -p "/project/$GID"
        chown root:"$GROUP" "/project/$GID"
        chmod 2770 "/project/$GID"
        ln -sfT "/project/$GID" "/project/$GROUP"
        restorecon -F -R /project/$GID /project/$GROUP

    elif [[ "$OP" == "MOD" ]]; then
        # A group has been modified
        # We grep the log for all operations related to request $CONN that contain a uid
        USERNAMES=$(grep -oP "conn=$CONN op=[0-9]* SRCH base=\"uid=\K([a-z0-9A-Z_-]*)(?=,cn=users)" /var/log/dirsrv/slapd-*/access)

        # The operation that add users to a group would have requests with a uid
        # If we found none, $USERNAMES will be empty, and it means we don't have
        # anything to add to Slurm and /project
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
        done
        /opt/software/slurm/bin/sacctmgr add user ${USERNAMES} Account=${GROUP} -i

    elif [[ "$OP" == "DEL" ]]; then
        # A group has been removed.
        # Since we do not want to delete any data we only remove the
        # symlinks and remove the users from the slurm account.
        USERNAMES=$(/opt/software/slurm/bin/sacctmgr show user withassoc Account=$GROUP -i format=user --noheader -P)
        /opt/software/slurm/bin/sacctmgr remove user $USERNAMES Account=${GROUP} -i
        for USERNAME in $USERNAMES; do
            USER_HOME="/mnt/home/$USERNAME"
            rm "$USER_HOME/projects/$GROUP"
        done
    fi

    PREV_CONN="$CONN"
done