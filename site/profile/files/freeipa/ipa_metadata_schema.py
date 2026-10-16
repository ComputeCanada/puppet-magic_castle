#!/usr/libexec/platform-python
"""Provision additive LDAP schema for configured user and group metadata keys.

Run locally as root on the FreeIPA server. Existing attribute definitions and
previously permitted attributes are preserved, even if no longer configured.
"""
import argparse
import copy
import json
import re
import tempfile
import uuid

from ldap.schema import AttributeType, ObjectClass
from ipalib import api
from ipapython.dn import DN
from ipaserver.install.schemaupdate import update_schema


OBJECT_CLASSES = {'user': 'mcUserMetadata', 'group': 'mcGroupMetadata'}


def schema_oid(kind, name):
    """Stable UUID OIDs: independent of key ordering and organization PENs."""
    identifier = uuid.uuid5(
        uuid.NAMESPACE_URL,
        'https://github.com/ComputeCanada/puppet-magic_castle/ldap-schema/{}/{}'.format(
            kind, name.lower()),
    )
    return '2.25.{}'.format(identifier.int)


def schema_changes(schema, attributes):
    """Return LDIF for missing attributes and additive object-class changes."""
    names_by_entity = {}
    for entity, names in attributes.items():
        if entity not in OBJECT_CLASSES:
            raise ValueError('Unknown metadata entity: {}'.format(entity))
        names_by_entity[entity] = set()
        for name in names:
            if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z][A-Za-z0-9-]*', name):
                raise ValueError('Invalid LDAP attribute name: {!r}'.format(name))
            names_by_entity[entity].add(name.lower())

    definitions = []
    for name in sorted(set().union(*names_by_entity.values())):
        if schema.get_obj(AttributeType, name) is None:
            oid = schema_oid('attribute', name)
            if schema.get_obj(AttributeType, oid) is not None:
                raise ValueError('Schema OID already in use: {}'.format(oid))
            definitions.append(
                "attributeTypes: ( {} NAME '{}' EQUALITY caseExactMatch "
                "SYNTAX 1.3.6.1.4.1.1466.115.121.1.15 SINGLE-VALUE )".format(oid, name)
            )

    for entity, names in sorted(names_by_entity.items()):
        if not names:
            continue
        class_name = OBJECT_CLASSES[entity]
        existing = schema.get_obj(ObjectClass, class_name)
        if existing is None:
            oid = schema_oid('objectclass', class_name)
            if schema.get_obj(ObjectClass, oid) is not None:
                raise ValueError('Schema OID already in use: {}'.format(oid))
            object_class = ObjectClass(
                "( {} NAME '{}' SUP top AUXILIARY )".format(oid, class_name))
        else:
            if existing.kind != 2:  # python-ldap's AUXILIARY kind
                raise ValueError('{} must be an auxiliary object class'.format(class_name))
            object_class = copy.copy(existing)
        allowed = {name.lower() for name in object_class.may + object_class.must}
        missing = names - allowed
        if existing is None or missing:
            object_class.may = tuple(object_class.may) + tuple(sorted(missing))
            definitions.append('objectClasses: {}'.format(object_class))
    return 'dn: cn=schema\n' + '\n'.join(definitions) + '\n' if definitions else None


def provision(attributes, dry=False):
    ldap = api.Backend.ldap2
    ldif = schema_changes(ldap.schema, attributes)
    config = ldap.get_entry(
        DN(('cn', 'ipaconfig'), ('cn', 'etc'), api.env.basedn),
        ['ipauserobjectclasses', 'ipagroupobjectclasses'],
    )
    additions = {}
    for entity, names in attributes.items():
        if not names:
            continue
        setting = 'ipa{}objectclasses'.format(entity)
        classes = list(config.get(setting, []))
        class_name = OBJECT_CLASSES[entity]
        if class_name.lower() not in {name.lower() for name in classes}:
            additions[setting] = classes + [class_name]
    if not dry:
        if ldif:
            with tempfile.NamedTemporaryFile(mode='w', suffix='.ldif') as schema_file:
                schema_file.write(ldif)
                schema_file.flush()
                update_schema([schema_file.name], ldapi=True)
        if additions:
            config.update(additions)
            ldap.update_entry(config)
    return bool(ldif or additions)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('attributes_file', help='JSON mapping of user/group to metadata attribute names')
    parser.add_argument('--dry', action='store_true', help='exit 1 if setup is required')
    args = parser.parse_args()
    with open(args.attributes_file) as attributes_file:
        attributes = json.load(attributes_file)
    api.bootstrap(in_server=True, context='updates')
    api.finalize()
    api.Backend.ldap2.connect()
    try:
        changed = provision(attributes, dry=args.dry)
    finally:
        api.Backend.ldap2.disconnect()
    if args.dry and changed:
        raise SystemExit(1)
