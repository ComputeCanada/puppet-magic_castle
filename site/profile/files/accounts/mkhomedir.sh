#!/bin/bash

USERNAMES=${@}

if [ -z "${USERNAMES}" ]; then
    echo "$0 username1 [username2 ...]"
    exit
fi

for USERNAME in ${USERNAMES}; do
    USER_HOME="/mnt/home/$USERNAME"
    rsync -opg -r -u --chown=$USERNAME:$USERNAME --chmod=D700,F700 /etc/skel/ $USER_HOME
    restorecon -F -R $USER_HOME

    USER_SCRATCH="/scratch/$USERNAME"
    if [[ ! -d "$USER_SCRATCH" ]]; then
        mkdir -p $USER_SCRATCH
        ln -sfT $USER_SCRATCH "$USER_HOME/scratch"
        chown -h $USERNAME:$USERNAME $USER_SCRATCH "$USER_HOME/scratch"
        chmod 750 $USER_SCRATCH
        restorecon -F -R $USER_SCRATCH
    fi
done