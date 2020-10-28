#!/usr/libexec/platform-python
import argparse
import os
import sys

from ipalib import api, errors
from ipalib.cli import cli
from ipapython import ipautil
from ipaplatform.paths import paths

from six import text_type


def init_api():
    api.bootstrap_with_global_options(context="cli")
    api.add_plugin(cli)
    api.finalize()
    api.Backend.cli.create_context()


def user_add(uid, first, last, password, shell):
    kargs = dict(
        uid=text_type(uid),
        givenname=text_type(first),
        sn=text_type(last),
        userpassword=text_type(password),
        loginshell=text_type(shell),
    )
    try:
        uidnumber = os.stat("/mnt/home/" + uid).st_uid
    except:
        pass
    else:
        kargs["uidnumber"] = uidnumber

    # Try up to 5 times to add user to the database
    for _ in range(5):
        try:
            return api.Command.user_add(**kargs)
        except errors.DuplicateEntry:
            return
        except errors.DatabaseError:
            continue
    else:
        raise Exception("Could not add user: {uid}".format(**kargs))


def group_add(name):
    try:
        return api.Command.group_add(name)
    except errors.DuplicateEntry:
        return


def group_add_members(group, members):
    api.Command.group_add_member(
        cn=text_type(group), user=list(map(text_type, members))
    )


def kinit(username, password):
    ipautil.run([paths.KINIT, username], stdin=password + "\n")


def kdestroy():
    ipautil.run([paths.KDESTROY])


def main(users, sponsor):
    admin_passwd = os.environ["IPA_ADMIN_PASSWD"]
    guest_passwd = os.environ["IPA_GUEST_PASSWD"]
    init_api()
    kinit("admin", admin_passwd)
    added_users = set()
    for username in users:
        user = user_add(
            username,
            first=username,
            last=username,
            password=guest_passwd,
            shell="/bin/bash",
        )
        if user is not None:
            added_users.add(username)
    if sponsor:
        group = u"def-" + sponsor
        group_add(group)
        group_add_members(group, users)
    kdestroy()

    # configure user password
    for username in added_users:
        kinit(username, "\n".join([guest_passwd] * 3))
        kdestroy()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Add a batch of generic users with the same sponsor"
    )
    parser.add_argument("users", nargs="+", help="list of usernames to create")
    parser.add_argument("--sponsor", help="name of the sponsor if any")
    args = parser.parse_args()
    main(args.users, args.sponsor)
