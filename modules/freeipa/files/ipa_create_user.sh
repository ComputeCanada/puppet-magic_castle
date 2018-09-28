#!/bin/bash
ADMIN_PASSWD=$1
USERNAME=$2
PASSWORD=$3

echo $ADMIN_PASSWD | kinit admin
echo $PASSWORD | ipa user-add $USERNAME --first "$USERNAME" --last "$USERNAME" --cn "$USERNAME" --shell /bin/bash --password
kdestroy
echo -e "$PASSWORD\n$PASSWORD\n$PASSWORD" | kinit $USERNAME
kdestroy
mkhomedir_helper $USERNAME