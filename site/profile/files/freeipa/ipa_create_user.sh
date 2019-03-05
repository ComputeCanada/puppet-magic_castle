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

for USERNAME in ${USERNAMES[@]}; do
    # Skip if the username has already been created
    if [[ -d "/home/$USERNAME" ]] ; then
        continue
    fi

    echo $IPA_ADMIN_PASSWD | kinit admin
    echo $IPA_GUEST_PASSWD | ipa user-add $USERNAME --first "-" --last "-" --cn "$USERNAME" --shell /bin/bash --password
    kdestroy
    echo -e "$IPA_GUEST_PASSWD\n$IPA_GUEST_PASSWD\n$IPA_GUEST_PASSWD" | kinit $USERNAME
    kdestroy
    mkhomedir_helper $USERNAME 0027

    # Project space
    if [ -n "${SPONSOR}" ]; then
        echo $IPA_ADMIN_PASSWD | kinit admin
        GROUP="def-$SPONSOR"
        if ! ipa group-find "$GROUP" ; then
            GID=$(ipa group-add "$GROUP" | grep -oP '(?<=GID: )[0-9]*')
            mkdir -p "/project/$GID"
            chown root:"$GROUP" "/project/$GID"
            chmod 770 "/project/$GID"
            ln -sfT "/project/$GID" "/project/$GROUP"
        fi
        ipa group-add-member "$GROUP" --user="$USERNAME"
        kdestroy

        PRO_USER="/project/$GROUP/$USERNAME"
        mkdir -p $PRO_USER
        mkdir -p "/home/$USERNAME/projects"
        ln -sfT "/project/$GROUP" "/home/$USERNAME/projects/$GROUP"
        ln -sfT "/project/$GROUP" "/home/$USERNAME/project"
        chown -R $USERNAME:$USERNAME "/home/$USERNAME/projects" "/home/$USERNAME/project" $PRO_USER
        chmod 750 "/home/$USERNAME/projects" $PRO_USER
    fi

    # Scratch spaces
    SCR_USER="/scratch/$USERNAME"
    mkdir -p $SCR_USER
    ln -sfT $SCR_USER "/home/$USERNAME/scratch"
    chown -h $USERNAME:$USERNAME $SCR_USER "/home/$USERNAME/scratch"
    chmod 750 $SCR_USER
done