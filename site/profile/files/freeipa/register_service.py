"""Register a service with `ipa console`; IPA_SERVICE_CONFIG names its JSON file."""
import json
import os

config_path = os.environ.get('IPA_SERVICE_CONFIG')
if not config_path:
    raise RuntimeError('IPA_SERVICE_CONFIG must name the service JSON configuration file')
with open(config_path, encoding='utf-8') as config_file:
    config = json.load(config_file)

commands = [
    {'method': 'service_add', 'params': [[config['service']], {}]},
]
for alias in config['aliases']:
    commands.append({'method': 'service_add_principal',
                     'params': [[config['service'], alias], {}]})
for name, options in config['permissions'].items():
    commands.append({'method': 'permission_add', 'params': [[name], options]})
for name in config['custom_privileges']:
    commands.append({'method': 'privilege_add', 'params': [[name], {}]})
commands.append({'method': 'role_add',
                 'params': [[config['role']], {'description': config['description']}]})
for name, permissions in config['custom_privileges'].items():
    for permission in permissions:
        commands.append({'method': 'privilege_add_permission',
                         'params': [[name], {'permission': permission}]})
for privilege in config['privileges']:
    commands.append({'method': 'role_add_privilege',
                     'params': [[config['role']], {'privilege': privilege}]})
commands.append({'method': 'role_add_member',
                 'params': [[config['role']], {'service': config['service']}]})

results = api.Command.batch(*commands)['results']
if len(results) != len(commands):
    raise RuntimeError('incomplete service registration batch')
for command, result in zip(commands, results):
    if result.get('error'):
        # Existing objects and aliases are expected on subsequent refreshes.
        allowed = {
            'service_add': 'DuplicateEntry',
            'permission_add': 'DuplicateEntry',
            'privilege_add': 'DuplicateEntry',
            'role_add': 'DuplicateEntry',
            'service_add_principal': 'AlreadyContainsValueError',
        }
        expected_error = allowed.get(command['method'])
        if expected_error is None or result.get('error_name') != expected_error:
            raise RuntimeError('{}: {}'.format(command['method'], result['error']))

# Membership commands can report failures without a top-level batch error.
# Verify the desired assignments, including memberships that already existed.
for name, permissions in config['custom_privileges'].items():
    assigned = api.Command.privilege_show(name)['result'].get('memberof_permission', [])
    for permission in permissions:
        if permission not in assigned:
            raise RuntimeError('permission assignment failed: {} -> {}'.format(permission, name))
role = api.Command.role_show(config['role'])['result']
for privilege in config['privileges']:
    if privilege not in role.get('memberof_privilege', []):
        raise RuntimeError('privilege assignment failed: {}'.format(privilege))
principal = config['service'] + '@' + config['realm']
if principal not in role.get('member_service', []):
    raise RuntimeError('service assignment failed: {}'.format(principal))
service = api.Command.service_show(config['service'])['result']
for alias in config['aliases']:
    principal = alias + '@' + config['realm']
    if principal not in service.get('krbprincipalname', []):
        raise RuntimeError('service alias assignment failed: {}'.format(principal))
