#!/usr/libexec/platform-python
"""Map Globus identity usernames to FreeIPA accounts via ipaidpsub."""
import argparse
import json
import pwd
import os
import socket
import tempfile
from contextlib import contextmanager
import sys
import traceback
from uuid import UUID

from gssapi.exceptions import GSSError
from ipalib import api, errors
from ipalib.kinit import kinit_keytab


POSIX_CONNECTOR = '145812c8-decc-41f1-83cf-bb2a85a2a70b'
TIMEOUT = 5


@contextmanager
def connect(config):
    # A private FILE cache isolates concurrent invocations and is removed even
    # when kinit, API initialization, or the lookup fails.
    with tempfile.TemporaryDirectory(prefix='globus-freeipa-') as directory:
        ccache = 'FILE:' + os.path.join(directory, 'ccache')
        kinit_keytab(config['principal'], config['keytab'], ccache_name=ccache)
        previous_timeout = socket.getdefaulttimeout()
        socket.setdefaulttimeout(TIMEOUT)
        try:
            api.bootstrap(context='cli')
            api.finalize()
            api.Backend.rpcclient.connect(ccache=ccache)
            yield api
        finally:
            try:
                if api.isdone('finalize') and api.Backend.rpcclient.isconnected():
                    api.Backend.rpcclient.disconnect()
            finally:
                socket.setdefaulttimeout(previous_timeout)


def lookup(client, username):
    # Include locked accounts in the search so duplicate identities are always
    # rejected. Do not accept a partial result if the server truncates a search.
    response = client.Command.user_find(
        ipaidpsub=username, sizelimit=2, timelimit=TIMEOUT,
        preserved=False,
    )
    entries = response['result']
    if response.get('truncated') or len(entries) > 1:
        raise ValueError('ambiguous or truncated IPA mapping')
    if not entries:
        return None
    attrs = entries[0]
    # The API may return tuples or lists; preserve the identifier exactly.
    if tuple(attrs.get('ipaidpsub', ())) != (username,):
        return None
    if attrs.get('nsaccountlock') is not False:
        return None
    uids = attrs.get('uid', ())
    if len(uids) != 1 or not isinstance(uids[0], str):
        return None
    uid = uids[0]
    try:
        account = pwd.getpwnam(uid)
    except KeyError:
        return None
    if account.pw_name != uid or account.pw_uid == 0:
        return None
    return uid


def map_identities(document, client, all_matches=False):
    if (not isinstance(document, dict) or
            document.get('DATA_TYPE') != 'identity_mapping_input#1.0.0' or
            not isinstance(document.get('identities'), list)):
        raise ValueError('invalid identity mapping input')
    identities = document['identities']
    for identity in identities:
        if not isinstance(identity, dict) or not isinstance(identity.get('id'), str):
            raise ValueError('invalid identity')
        # Raise a ValueError if the provided UUID is invalid
        UUID(identity['id'])
    results = []
    for identity in identities:
        username = identity.get('username')
        if not isinstance(username, str) or not username:
            continue
        uid = lookup(client, username)
        if uid is not None:
            mapping = {'id': identity['id'], 'output': uid}
            if mapping not in results:
                results.append(mapping)
            if not all_matches:
                break
    return results


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('-c', required=True, help='Globus connector UUID')
    parser.add_argument('-s', help='Globus storage gateway UUID')
    parser.add_argument('-a', action='store_true', help='return all mappings')
    parser.add_argument('--config', default='/etc/globus/freeipa-mapping.json')
    args = parser.parse_args(argv)
    output = {'DATA_TYPE': 'identity_mapping_output#1.0.0', 'result': []}
    status = 0
    try:
        if args.c != POSIX_CONNECTOR:
            raise ValueError('only the POSIX connector is supported')
        document = json.load(sys.stdin)
        with open(args.config) as config_file:
            config = json.load(config_file)
        with connect(config) as client:
            results = map_identities(document, client, args.a)
        output['result'] = results
    except Exception as error:
        # Fail closed for IPA, Kerberos, transport and input errors, without
        # exposing credentials or identity data in diagnostics.
        print('FreeIPA identity mapping failed ({})'.format(type(error).__name__), file=sys.stderr)
        status = 1
    json.dump(output, sys.stdout)
    sys.stdout.write('\n')
    return status


if __name__ == '__main__':
    sys.exit(main())
