#!/usr/libexec/platform-python
import argparse
import logging
import os
import time
import grp
import pwd

from ipalib import api, errors
from ipalib.cli import cli
from ipapython import ipautil
from ipaplatform.paths import paths

from six import text_type

iau_logger = logging.getLogger("IPA_CREATE_USER.PY")
iau_logger.setLevel(logging.INFO,)
formatter = logging.Formatter(
    fmt="%(asctime)s.%(msecs)03d %(levelname)s {%(module)s} [%(funcName)s] %(message)s",
    datefmt="%Y-%m-%d,%H:%M:%S",
)
handler = logging.StreamHandler()
handler.setFormatter(fmt=formatter)
iau_logger.addHandler(handler)


def init_api():
    api.bootstrap_with_global_options(context="cli")
    api.add_plugin(cli)
    api.finalize()
    api.Backend.cli.create_context()


def user_add(uid, first, last, password, shell, sshpubkeys, idp_user_id=None,
             uidnumber=None, gidnumber=None):
    kargs = dict()
    kargs['uid'] = text_type(uid)
    kargs['givenname'] = text_type(first)
    kargs['sn'] = text_type(last)
    if password:
        kargs['userpassword'] = text_type(password)
    if sshpubkeys:
        kargs['ipasshpubkey'] = list(map(text_type, sshpubkeys))
    kargs['loginshell'] = text_type(shell)
    if idp_user_id is not None:
        kargs['ipaidpsub'] = text_type(idp_user_id)

    if uidnumber is not None:
        kargs["uidnumber"] = uidnumber
    if gidnumber is not None:
        kargs["gidnumber"] = gidnumber

    # Try up to 5 times to add user to the database
    for i in range(1, 6):
        try:
            iau_logger.info("adding user {uid} (Try {i} / 5)".format(uid=uid, i=i))
            return api.Command.user_add(**kargs)
        except errors.DuplicateEntry:
            iau_logger.warning(
                "User {uid} already in database (Try {i} / 5)".format(uid=uid, i=i,)
            )
            return
        except errors.DatabaseError as err:
            iau_logger.error(
                "Database error while trying to create user: {uid} (Try {i} / 5). Exception: {err}".format(
                    uid=uid, i=i, err=err
                )
            )
            # Give time to slapd to cleanup
            time.sleep(1.0)
    else:
        raise Exception("Could not add user: {uid}".format(**kargs))


def group_add_members(group, members, page_size=50):
    for i in range(0, len(members), page_size):
        iau_logger.info("adding members {begin}:{end} to {group}".format(begin=members[i], end=members[min(i+page_size, len(members)-1)],group=group))
        api.Command.group_add_member(
            cn=text_type(group), user=list(map(text_type, members[i:i+page_size]))
        )


def kinit(username, password):
    ipautil.run([paths.KINIT, username], stdin=password + "\n")


def kdestroy():
    ipautil.run([paths.KDESTROY])


def dry_run(users, groups):
    "Verify if changes are required and true if needed."
    users = set(users)
    if groups:
        for group in groups:
            try:
                members = set(grp.getgrnam(group).gr_mem)
            except KeyError:
                return True
            if not members.issuperset(users):
                return True
    else:
        for user in users:
            try:
                pwd.getpwnam(user)
            except KeyError:
                return True
    return False


def main(users, groups, passwd, sshpubkeys, idp_user_id=None, uid=None, gid=None):
    init_api()
    added_users = set()
    for offset, username in enumerate(users):
        user = user_add(
            username,
            first=username,
            last=username,
            password=passwd,
            shell="/bin/bash",
            sshpubkeys=sshpubkeys,
            idp_user_id=idp_user_id,
            uidnumber=None if uid is None else uid + offset,
            gidnumber=None if gid is None else gid + offset,
        )
        if user is not None:
            added_users.add(username)

    if groups:
        for group in groups:
            group_add_members(group, users)

    if passwd:
        # configure user password
        for username in added_users:
            kinit(username, "\n".join([passwd] * 3))
            kdestroy()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Add a batch of users with common a password and groups"
    )
    parser.add_argument("users", nargs="+", help="list of usernames to create")
    parser.add_argument("--group", action='append', help="group the users will be member of (can be specified multiple times)")
    parser.add_argument("--passwd", help="users's password")
    parser.add_argument("--sshpubkey", action="append", help="SSH public key (can be specified multiple times)")
    parser.add_argument("--idp-user-id", help="external IdP user identifier, set only at creation (single user only)")
    parser.add_argument("--uid", type=int, help="starting numeric user ID, incremented for each username")
    parser.add_argument("--gid", type=int, help="starting primary group ID, incremented for each username")
    parser.add_argument("--dry", help="determine if changes are required", action='store_true')
    args = parser.parse_args()
    for option in ('uid', 'gid'):
        value = getattr(args, option)
        if value is not None and value < 1:
            parser.error("--{} must be a positive integer".format(option))
    if args.idp_user_id is not None:
        if not args.idp_user_id:
            parser.error("--idp-user-id must not be empty")
        if len(args.users) != 1:
            parser.error("--idp-user-id requires a single user")

    if args.passwd is not None:
        passwd = args.passwd
    elif "IPA_USER_PASSWD" in os.environ:
        passwd = os.environ["IPA_USER_PASSWD"]
    else:
        passwd = None

    if args.dry:
        if dry_run(args.users, args.group):
            exit(1)
    else:
        main(
            users=args.users,
            groups=args.group,
            passwd=passwd,
            sshpubkeys=args.sshpubkey,
            idp_user_id=args.idp_user_id,
            uid=args.uid,
            gid=args.gid,
        )
