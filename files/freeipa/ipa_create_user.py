#!/usr/bin/env python
import argparse
import os
import sys

from ipalib import api, errors
from ipalib.cli import cli
from ipapython import ipautil
from ipaplatform.paths import paths

def init_api():
    api.bootstrap_with_global_options(context='cli')
    api.add_plugin(cli)
    api.finalize()
    api.Backend.cli.create_context()

def user_add(uid, first, last, password, shell):
    try:
        return api.Command.user_add(uid=unicode(uid),
                                    givenname=unicode(first),
                                    sn=unicode(last),
                                    userpassword=unicode(password),
                                    loginshell=unicode(shell))
    except errors.DuplicateEntry:
        return

def group_add(name):
    try:
        return api.Command.group_add(name)
    except errors.DuplicateEntry:
        return

def group_add_members(group, members):
    api.Command.group_add_member(cn=unicode(group),
                                 user=list(map(unicode, members)))

def kinit(username, password):
    ipautil.run([paths.KINIT, username], stdin=password+'\n')

def kdestroy():
    ipautil.run([paths.KDESTROY])

def main(users, sponsor):
    admin_passwd = os.environ['IPA_ADMIN_PASSWD']
    guest_passwd = os.environ['IPA_GUEST_PASSWD']
    init_api()
    kinit('admin', admin_passwd)
    for user in users:
        user_add(user, first=user, last=user, password=guest_passwd, shell='/bin/bash')
    if sponsor:
        group = u'def-' + sponsor
        group_add(group)
        group_add_members(group, users)        
    kdestroy()

    # configure user password
    for user in users:
        kinit(user, "\n".join([guest_passwd]*3))
        kdestroy()

if __name__ == "__main__" :
    parser = argparse.ArgumentParser(description='Add a batch of generic users with the same sponsor')
    parser.add_argument('users', nargs='+', help='list of usernames to create')
    parser.add_argument('--sponsor', help='name of the sponsor if any')
    args = parser.parse_args()
    main(args.users, args.sponsor)