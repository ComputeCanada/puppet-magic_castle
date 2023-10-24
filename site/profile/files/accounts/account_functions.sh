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
        echo "$USERNAME is not showing up in SSSD after 1min - cannot make its home."
        return 1
    fi

    local USER_HOME=$(SSS_NSS_USE_MEMCACHE=no getent passwd $USERNAME | cut -d: -f6)
    local MNT_USER_HOME="/mnt${USER_HOME}"
    for i in $(seq 1 5); do
        rsync -opg -r -u --chown=$USERNAME:$USERNAME --chmod=Dg-rwx,o-rwx,Fg-rwx,o-rwx,u+X /etc/skel.ipa/ ${MNT_USER_HOME}
        if [ $? -eq 0 ]; then
            break
        else
            sleep 5
        fi
    done
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
    fi
}

