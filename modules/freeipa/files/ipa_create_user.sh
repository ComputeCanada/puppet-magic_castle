#!/bin/bash

USERNAME=$1
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
echo $IPA_GUEST_PASSWD | ipa user-add $USERNAME --first "-" --last "-" --cn "$USERNAME" --shell /bin/bash --password
kdestroy
echo -e "$IPA_GUEST_PASSWD\n$IPA_GUEST_PASSWD\n$IPA_GUEST_PASSWD" | kinit $USERNAME
kdestroy
mkhomedir_helper $USERNAME