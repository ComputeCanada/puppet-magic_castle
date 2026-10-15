#!/usr/libexec/platform-python
"""Manage selected attributes on existing FreeIPA users or groups.

Omitted attributes are unmanaged. An empty value clears an attribute, matching
FreeIPA's setattr semantics. The schema setup enables the metadata object classes
for new entries; this helper also attaches them to existing entries.
"""
import argparse

from ipalib import api, errors
from six import text_type

from ipa_create_user import init_api


def metadata_attribute(value):
    attribute, separator, value = value.partition('=')
    if not separator or not attribute.strip():
        raise argparse.ArgumentTypeError('metadata must be ATTRIBUTE=VALUE')
    return attribute.strip().lower(), value.strip()


def update_metadata(names, metadata, dry=False, entity='user'):
    """Return True if any managed attribute differs; dry mode never writes."""
    changed = False
    metadata_class = {'user': 'mcUserMetadata', 'group': 'mcGroupMetadata'}[entity]
    show = getattr(api.Command, entity + '_show')
    modify = getattr(api.Command, entity + '_mod')
    defaults = api.Command.config_show()['result'].get('ipa{}objectclasses'.format(entity), [])
    manage_class = metadata_class.lower() in {name.lower() for name in defaults}
    for name in names:
        entry = show(text_type(name), all=True, raw=True)['result']
        classes = {name.lower() for name in entry.get('objectclass', [])}
        add_class = manage_class and metadata_class.lower() not in classes
        attributes = []
        for attribute, value in metadata.items():
            current = entry.get(attribute, [])
            if not isinstance(current, (list, tuple)):
                current = [current]
            current = [text_type(item) for item in current]
            desired = [value] if value else []
            if current != desired:
                attributes.append(text_type('{}={}'.format(attribute, value)))
        if attributes or add_class:
            changed = True
            if not dry:
                try:
                    options = {}
                    if attributes:
                        options['setattr'] = attributes
                    if add_class:
                        options['addattr'] = ['objectclass={}'.format(metadata_class)]
                    modify(text_type(name), **options)
                except errors.EmptyModlist:
                    # LDAP matching rules may consider differently cased values equal.
                    pass
    return changed


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('names', nargs='+', help='entries whose metadata is managed')
    parser.add_argument('--entity', choices=['user', 'group'], default='user')
    parser.add_argument('--metadata', action='append', type=metadata_attribute,
                        required=True, metavar='ATTRIBUTE=VALUE')
    parser.add_argument('--dry', action='store_true', help='exit 1 if changes are required')
    args = parser.parse_args()
    init_api()
    changed = update_metadata(args.names, dict(args.metadata), dry=args.dry, entity=args.entity)
    if args.dry and changed:
        raise SystemExit(1)
