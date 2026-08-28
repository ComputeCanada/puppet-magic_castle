api.Command.batch(
    {
        'method': 'group_add',
        'params': [[
            'host-enrollers',
        ], {
            'description': 'Accounts allowed to enroll hosts',
            'nonposix': True,
        }],
    },
    {
        'method': 'pwpolicy_add',
        'params': [[
            'host-enrollers',
        ], {
            'krbminpwdlife': 0,
            'krbmaxpwdlife': 0,
            'cospriority': 2,
        }],
    },
    {
        'method': 'user_add',
        'params': [[
            'host_enrollment',
        ], {
            'givenname': 'Host',
            'sn': 'Enrollment',
            'loginshell': '/sbin/nologin',
        }],
    },
    {
        'method': 'group_add_member',
        'params': [['host-enrollers'], {'user': 'host_enrollment'}],
    },
    {
        'method': 'privilege_add',
        'params': [[
            'Magic Castle Host Enrollment',
        ], {
            'description': 'Permissions required to enroll Magic Castle hosts',
        }],
    },
    {
        'method': 'privilege_add_permission',
        'params': [[
            'Magic Castle Host Enrollment',
        ], {
            'permission': 'System: Add Hosts',
        }],
    },
    {
        'method': 'privilege_add_permission',
        'params': [[
            'Magic Castle Host Enrollment',
        ], {
            'permission': 'System: Add krbPrincipalName to a Host',
        }],
    },
    {
        'method': 'privilege_add_permission',
        'params': [[
            'Magic Castle Host Enrollment',
        ], {
            'permission': 'System: Enroll a Host',
        }],
    },
    {
        'method': 'privilege_add_permission',
        'params': [[
            'Magic Castle Host Enrollment',
        ], {
            'permission': 'System: Manage Host Keytab',
        }],
    },
    {
        'method': 'privilege_add_permission',
        'params': [[
            'Magic Castle Host Enrollment',
        ], {
            'permission': 'System: Manage Host Certificates',
        }],
    },
    {
        'method': 'privilege_add_permission',
        'params': [[
            'Magic Castle Host Enrollment',
        ], {
            'permission': 'System: Manage Host Principals',
        }],
    },
    {
        'method': 'role_add',
        'params': [[
            'Magic Castle Host Enrollment',
        ], {
            'description': 'Enroll Magic Castle hosts',
        }],
    },
    {
        'method': 'role_add_privilege',
        'params': [[
            'Magic Castle Host Enrollment',
        ], {
            'privilege': 'Magic Castle Host Enrollment',
        }],
    },
    {
        'method': 'role_add_member',
        'params': [[
            'Magic Castle Host Enrollment',
        ], {
            'user': 'host_enrollment',
        }],
    },
)
