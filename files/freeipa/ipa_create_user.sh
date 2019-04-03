#!/bin/bash

USERNAMES=${*%${!#}}
LAST=${@:$#} # last parameter

if [[ "${LAST}" =~ "Sponsor=" ]]; then
    SPONSOR=${LAST#Sponsor=}
else
    USERNAMES+=($LAST)
fi

if [ -z "${USERNAMES}" ]; then
    echo "$0 username1 username2 ... [Sponsor=sponsor-name]"
    exit
fi

if [ -z "${IPA_ADMIN_PASSWD+xxx}" ]; then
    echo "Please enter your FreeIPA admin password: "
    read -sr IPA_PASSWORD_INPUT
    IPA_ADMIN_PASSWD="$IPA_PASSWORD_INPUT"
fi

if [ -z "${IPA_GUEST_PASSWD+xxx}" ]; then
    echo "Please enter the guest password: "
    read -sr GUEST_PASSWORD_INPUT
    IPA_GUEST_PASSWD="$GUEST_PASSWORD_INPUT"
fi

echo $IPA_ADMIN_PASSWD | kinit admin

if [ -n "${SPONSOR}" ]; then
    GROUP="def-$SPONSOR"
    if ! ipa group-find --group-name="$GROUP" &> /dev/null; then
        GID=$(ipa group-add "$GROUP" | grep -oP '(?<=GID: )[0-9]*')
        mkdir -p "/project/$GID"
        chown root:"$GROUP" "/project/$GID"
        chmod 770 "/project/$GID"
        ln -sfT "/project/$GID" "/project/$GROUP"
    fi
fi

for USERNAME in ${USERNAMES[@]}; do
    if ! ipa user-find --login=$USERNAME &> /dev/null; then
        echo $IPA_GUEST_PASSWD | ipa user-add $USERNAME --first "-" --last "-" --cn "$USERNAME" --shell /bin/bash --password
        echo -e "$IPA_GUEST_PASSWD\n$IPA_GUEST_PASSWD\n$IPA_GUEST_PASSWD" | kinit $USERNAME && kdestroy

        USER_HOME="/mnt/home/$USERNAME"
        if [[ ! -d "$USER_HOME" ]] ; then
            cp -r /etc/skel $USER_HOME
        fi
        chown -R $USERNAME:$USERNAME $USER_HOME

        # Project space
        if [ -n "${GROUP}" ]; then
            ipa group-add-member "$GROUP" --user="$USERNAME"
            PRO_USER="/project/$GROUP/$USERNAME"
            mkdir -p $PRO_USER
            mkdir -p "$USER_HOME/projects"
            ln -sfT "/project/$GROUP" "$USER_HOME/projects/$GROUP"
            chown -R $USERNAME:$USERNAME "$USER_HOME/projects" $PRO_USER
            chmod 750 "$USER_HOME/projects" $PRO_USER
        fi

        # Scratch spaces
        SCR_USER="/scratch/$USERNAME"
        mkdir -p $SCR_USER
        ln -sfT $SCR_USER "$USER_HOME/scratch"
        chown -h $USERNAME:$USERNAME $SCR_USER "$USER_HOME/scratch"
        chmod 750 $SCR_USER
    fi
done
restorecon -F -R /mnt/home
restorecon -F -R /project
restorecon -F -R /scratch
kdestroy -A