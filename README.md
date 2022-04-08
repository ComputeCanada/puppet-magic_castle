# Puppet Magic Castle

This repo contains the Puppet classes that are used to define the roles of the
instances in a Magic Castle cluster. The attribution of the roles is done in
`manifests/site.pp`. The functioning of the profile classes can be customized
by defined values in the hieradata. The following sections list the available
variables for each profile.

## profile::accounts

| Variable                                  | Type       | Description                                                                         | Default       |
| ----------------------------------------- | :--------  | :---------------------------------------------------------------------------------- | ------------- |
| `profile::accounts:::project_regex` | String | Regex to identify LDAP groups that should also be Slurm accounts | `'(ctb\|def\|rpp\|rrg)-[a-z0-9_-]*'` |

## profile::base

| Variable                         | Type   | Description                                                                             | Default    |
| -------------------------------- | :----- | :-------------------------------------------------------------------------------------- | ---------- |
| `profile::base::admin_email`     | String | Email of the cluster administrator, use to send log and report cluster related issues   | `undef`    |

## profile::consul

| Variable                       | Type   | Description                                                             | Default  |
| ------------------------------ | :----- | :---------------------------------------------------------------------- | -------- |
| `profile::consul::server_ip`   | String | IP address of the consul server                                         |          |

## profile::cvmfs

| Variable                                         | Type          | Description                                    | Default                                                              |
| ------------------------------------------------ | :------------ | :--------------------------------------------- | -------------------------------------------------------------------- |
| `profile::cvmfs::client::quota_limit`            | Integer       | Instance local cache directory soft quota (MB) | 4096                                                                 |
| `profile::cvmfs::client::repositories`           | Array[String] | List of CVMFS repositories to mount            | `['cvmfs-config.computecanada.ca', 'soft.computecanada.ca']`         |
| `profile::cvmfs::client::lmod_default_modules`   | Array[String] | List of lmod default modules                   | `['gentoo/2020', 'imkl/2020.1.217', 'gcc/9.3.0', 'openmpi/4.0.3']` |

## profile::fail2ban

| Variable                                      | Type                       | Description                                                                    | Default   |
| --------------------------------------------- | :------------------------- | :----------------------------------------------------------------------------- | --------- |
| `fail2ban::ignoreip`                          | Array[String]              | List of IP addresses that can never be banned (compatible with CIDR notation)  | `[]`      |
| `fail2ban::service_ensure`                    | Enum['running', 'stopped'] | Enable fail2ban service                                                        | `running` |


## profile::freeipa

| Variable                                         | Type    | Description                                                                         | Default  |
| ------------------------------------------------ | :-----  | :---------------------------------------------------------------------------------- | -------- |
| `profile::freeipa::base::admin_passwd`           | String  | Password of the FreeIPA admin account, also used by the clients to join the server  |          |
| `profile::freeipa::base::dns_ip`                 | String  | FreeIPA DNS server IP Address. Used by the client to join find the server           |          |
| `profile::freeipa::base::domain_name`            | String  | FreeIPA primary domain                                                              |          |
| `profile::freeipa::client::server_ip`            | String  | FreeIPA server ip address                                                           |          |
| `profile::freeipa::mokey::port`                  | Integer | Mokey internal web server port                                                      | `12345`  |
| `profile::freeipa::mokey::enable_user_signup`    | Boolean | Allow users to create an account on the cluster                                     | `true`   |
| `profile::freeipa::mokey::require_verify_admin`  | Boolean | Require a FreeIPA to enable Mokey created account before usage                      | `true`   |

## profile::nfs

| Variable                           | Type   | Description                            | Default  |
| ---------------------------------- | :----- | :------------------------------------- | -------- |
| `profile::nfs::client::server_ip`  | String | IP address of the NFS server           | `undef`  |


## profile::reverse_proxy

| Variable                                       | Type   | Description                                                             | Default   |
| ---------------------------------------------- | :----- | :---------------------------------------------------------------------- | --------- |
| `profile::reverse_proxy::domain_name`          | String | Domain name corresponding to the main DNS record A registered           |           |
| `profile::reverse_proxy::jupyterhub_subdomain` | String | Subdomain name used to create the vhost for JupyterHub                  | `jupyter` |
| `profile::reverse_proxy::ipa_subdomain`        | String | Subdomain name used to create the vhost for FreeIPA                     | `ipa`     |
| `profile::reverse_proxy::mokey_subdomain`      | String | Subdomain name used to create the vhost for Mokey                       | `mokey`   |

## profile::slurm

| Variable                              | Type    | Description                                                             | Default  |
| ------------------------------------- | :------ | :---------------------------------------------------------------------- | -------- |
| `profile::slurm::base::cluster_name`  | String  | Name of the cluster                                                     |          |
| `profile::slurm::base::munge_key`     | String  | Base64 encoded Munge key                                                |          |
| `profile::slurm::base::slurm_version`  | Enum[19.05, 20.11, 21.08]  | Slurm version to install                            | 21.08    |
| `profile::slurm::base::os_reserved_memory`  | Integer  | Quantity of memory in MB reserved for the operating system on the compute nodes | 512 |
| `profile::slurm::base::enable_x11_forwarding`  | Boolean  | Enable Slurm's built-in X11 forwarding capabilities           | `true`   |
| `profile::slurm::accounting::password` | String  | Password used by for SlurmDBD to connect to MariaDB                    |          |
| `profile::slurm::accounting::dbd_port` | Integer | SlurmDBD service listening port                                        |          |
| `profile::slurm::controller::selinux_context` | String | SELinux context for jobs (used only with Slurm >= 21.08)         | `user_u:user_r:user_t:s0` |

## profile::squid

| Variable                              | Type           | Description                                                                 | Default  |
| ------------------------------------- | :------------- | :-------------------------------------------------------------------------- | -------- |
| `profile::squid::port`                | Integer        | Squid service listening port                                                | 3128     |
| `profile::squid::cache_size`          | Integer        | Amount of disk space (MB) that can be used by Squid service                 | 4096     |
| `profile::squid::cvmfs_acl_regex`     | Array[String]  | List of regexes corresponding to CVMFS stratum users are allowed to access  | `['^(cvmfs-.*\.computecanada\.ca)$', '^(.*-cvmfs\.openhtc\.io)$', '^(cvmfs-.*\.genap\.ca)$']`     |

## profile::users

| Variable                              | Type           | Description                                                                 | Default  |
| ------------------------------------- | :------------- | :-------------------------------------------------------------------------- | -------- |
| `profile::users::ldap::users` | Hash[Hash] | Dictionary of users to be created in LDAP | |
| `profile::users::local::users` | Hash[Hash] | Dictionary of users to be created locally | |

### profile::users::ldap::users

A batch of 10 LDAP users, user01 to user10, can be defined in hieradata as:
```
profile::users::ldap::users:
  user:
    count: 10
    passwd: user.password.is.easy.to.remember
    groups: ['def-sponsor00']
```

A single LDAP user can be defined as:
```
profile::users::ldap::users:
  alice:
    passwd: user.password.is.easy.to.remember
    groups: ['def-sponsor00']
    public_keys: ['ssh-rsa ... user@local', 'ssh-ecdsa ...']
```

### profile::users::local::users

A local user `bob` can be defined in hieradata as:
```
profile::users::local::users:
  bob:
    groups: ['group1', 'group2']
    public_keys: ['ssh-rsa...', 'ssh-dsa']
    # sudoer: false
    # selinux_user: 'unconfined_u'
    # mls_range: ''s0-s0:c0.c1023'
```

## profile::workshop

| Variable                          | Type   | Description                                                                     | Default                  |
| --------------------------------- | :----- | :------------------------------------------------------------------------------ | ------------------------ |
| `profile::workshop::userzip_url`  | String | URL pointing to a zip that needs to be extracted in each guest account's home   | `''`                     |
| `profile::workshop::userzip_path` | String | Path on the nfs server where to save the userzip archive                        | `'/project/userzip.zip'` |

## profile::mfa

| Variable                 | Type                | Description                        | Default |
| ------------------------ | :------------------ | :--------------------------------- | ------- |
| `profile::mfa::provider` | Enum['none', 'duo'] | MFA provider for node tagged 'mfa' | 'none'  |

## duo_unix

| Variable             | Type   | Description                  | Default                  |
| -------------------- | :----- | :--------------------------- | ------------------------ |
| `duo_unix::usage`    | String | Either login or pam          | `login`                  |
| `duo_unix::ikey`     | String | Duo integration              | `''`                     |
| `duo_unix::skey`     | String | Duo secret key               | `''`                     |
| `duo_unix::host`     | String | Duo api host                 | `''`                     |
| `duo_unix::motd`     | String | Enable motd                  | `no`                     |
| `duo_unix::failmode` | String | Failure mode, secure or safe | `safe`                   |