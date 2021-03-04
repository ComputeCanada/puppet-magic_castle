#!/bin/bash

# mkproject.sh watches 389-ds access log for operations related to group
# with a predefined prefix ($PROJECT_PREFIX) with the intent of automatically
# manipulate Slurm accounts and folder under /project associated with these
# groups

# Three operations are currently supported: ADD, MOD and DEL.
# - ADD triggers a creation of Slurm account and directory under /project
# - MOD triggers either the additions of users to the associated Slurm
#   accounts and their folder under /project/GID/`username`
#   or it trigger the removals of the users from the associated Slurm account
#   and the removal of the symlink from the users home to the project folder.
# - DEL trigger the removal of all users from the associated Slurm account
#   and the removal of the symlink to the project from all previous member
#   home folders.
#
# The script is currently unable to detect changes to groups when done via
# the 389-sd automember plugin, because these automember plugin actions
# produce no trace in 389-ds access logs.

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

    # We wait for the operation $CONN to be completed.
    # Taken from StackExchange:
    # https://unix.stackexchange.com/questions/416150/make-tail-f-exit-on-a-broken-pipe
    {
        grep --line-buffered -q -m 1 "conn=$CONN op=[0-9]* UNBIND";
        kill -s PIPE "$!";
    } < <(tail -n +0 -F /var/log/dirsrv/slapd-*/access 2> /dev/null)

    # We support three operations : ADD, MOD or DEL
    if [[ "$OP" == "ADD" ]]; then
        # A new group has been created
        # We create the associated account in slurm
        /opt/software/slurm/bin/sacctmgr add account $GROUP -i

        # We clean the SSSD cache before recovering the group GID.
        # This is in case the group existed before with a different gid.
        GID=$(sss_cache -g $GROUP && sleep 5 && getent group $GROUP | cut -d: -f3)

        # Then we create the project folder
        mkdir -p "/project/$GID"
        chown root:"$GROUP" "/project/$GID"
        chmod 2770 "/project/$GID"
        ln -sfT "/project/$GID" "/project/$GROUP"
        restorecon -F -R /project/$GID /project/$GROUP

    elif [[ "$OP" == "MOD" ]]; then
        # A group has been modified
        # We grep the log for all operations related to request $CONN that contain a uid
        USERNAMES=$(grep -oP "conn=$CONN op=[0-9]* SRCH base=\"uid=\K([a-z0-9A-Z_-]*)(?=,cn=users)" /var/log/dirsrv/slapd-*/access)

        # The operation that add users to a group would have operations with a uid.
        # If we found none, $USERNAMES will be empty, and it means we don't have
        # anything to add to Slurm and /project
        if [[ ! -z "$USERNAMES" ]]; then
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
        else
            # If group has been modified but no uid were found in the log, it means
            # user(s) have been removed from the groups.
            # We identify which ones by comparing Slurm account with group.
            USER_GROUP=$(sss_cache -g $GROUP && sleep 5 && getent group $GROUP | cut -d: -f4 | tr "," "\n" | sort)
            SLURM_ACCOUNT=$(/opt/software/slurm/bin/sacctmgr list assoc account=$GROUP format=user --noheader -p | cut -d'|' -f1 | awk NF | sort)
            USERNAMES=$(comm -2 -3 <(echo "$SLURM_ACCOUNT") <(echo "$USER_GROUP"))
            if [[ ! -z "$USERNAMES" ]]; then
                /opt/software/slurm/bin/sacctmgr remove user $USERNAMES Account=${GROUP} -i
                for USERNAME in $USERNAMES; do
                    USER_HOME="/mnt/home/$USERNAME"
                    rm "$USER_HOME/projects/$GROUP"
                done
            fi
        fi
    elif [[ "$OP" == "DEL" ]]; then
        # A group has been removed.
        # Since we do not want to delete any data we only remove the
        # symlinks and remove the users from the slurm account.
        USERNAMES=$(/opt/software/slurm/bin/sacctmgr list assoc account=$GROUP format=user --noheader -p | cut -d'|' -f1 | awk NF | sort)
        if [[ ! -z "$USERNAMES" ]]; then
            /opt/software/slurm/bin/sacctmgr remove user $USERNAMES Account=${GROUP} -i
            for USERNAME in $USERNAMES; do
                USER_HOME="/mnt/home/$USERNAME"
                rm "$USER_HOME/projects/$GROUP"
            done
        fi
    fi

    PREV_CONN="$CONN"
done