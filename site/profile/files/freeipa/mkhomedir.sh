#!/bin/bash

USERNAMES=${@}

if [ -z "${USERNAMES}" ]; then
    echo "$0 username1 [username2 ...]"
    exit
fi

for USERNAME in ${USERNAMES}; do
    USER_HOME="/mnt/home/$USERNAME"
    if [[ ! -d "$USER_HOME" ]] ; then
        cp -r /etc/skel $USER_HOME
        chmod 700 $USER_HOME
        chown -R $USERNAME:$USERNAME $USER_HOME

        restorecon -F -R $USER_HOME
        # Scratch space
        SCR_USER="/scratch/$USERNAME"
        mkdir -p $SCR_USER
        ln -sfT $SCR_USER "$USER_HOME/scratch"
        chown -h $USERNAME:$USERNAME $SCR_USER "$USER_HOME/scratch"
        chmod 750 $SCR_USER
        restorecon -F -R $SCR_USER
    fi
done