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
| `profile::accounts:::skel_archives` | Array[Struct[{filename => String[1], source => String[1]}]] | List of archives that will be extracted and copied in each FreeIPA user's home folder when first created. | `[]` |

### profile::accounts::skel_archives example
```
profile::accounts:::skel_archives:
  - filename: hss-programing-lab-2022.zip
    source: https://github.com/ComputeCanada/hss-programing-lab-2022/archive/refs/heads/main.zip
  - filename: hss-training-topic-modeling.tar.gz
    source: https://github.com/ComputeCanada/hss-training-topic-modeling/archive/refs/heads/main.tar.gz
```

## profile::base

| Variable                         | Type   | Description                                                                             | Default    |
| -------------------------------- | :----- | :-------------------------------------------------------------------------------------- | ---------- |
| `profile::base::version`     | String | Current version number of Magic Castle  | `'12.0.0'` |
| `profile::base::admin_email`     | String | Email of the cluster administrator, use to send log and report cluster related issues   | `undef`    |

## profile::ceph
| Variable                         | Type   | Description                                                                             | Default    |
| -------------------------------- | :----- | :-------------------------------------------------------------------------------------- | ---------- |
| `profile::ceph::share_name` | String | CEPH share name |  |
| `profile::ceph::access_key` | String | CEPH share access key |  |
| `profile::ceph::export_path`| String | Path of the share as exported by the monitors |  |
| `profile::ceph::mon_host`   | Array[String] | List of CEPH monitor hostnames | |
| `profile::ceph::mount_binds`| Array[String] | List of CEPH share folders that will bind mounted under `/` | `[]`  |
| `profile::ceph::mount_name` | String | Name to give to the CEPH share once mounted under `/mnt` | `'cephfs01'` |
| `profile::ceph::binds_fcontext_equivalence` | String | SELinux file context equivalence for the CEPH share | '`/home`' |


## profile::consul

| Variable                       | Type   | Description                                                             | Default  |
| ------------------------------ | :----- | :---------------------------------------------------------------------- | -------- |
| `profile::consul::servers`   | Array[String] | IP addresses of the consul servers                                         |          |

## profile::cvmfs

| Variable                                         | Type          | Description                                    | Default                                                              |
| ------------------------------------------------ | :------------ | :--------------------------------------------- | -------------------------------------------------------------------- |
| `profile::cvmfs::client::quota_limit` | Integer | Instance local cache directory soft quota (MB) | 4096 |
| `profile::cvmfs::client::initial_profile` | String | Path to shell script initializing software stack environment variables | Depends on the chosen software stack |
| `profile::cvmfs::client::extra_site_env_vars` | Hash[String, String] | Map of environment variables that will be exported before sourcing profile shell scripts. | `{ }` |
| `profile::cvmfs::client::repositories` | Array[String] | List of CVMFS repositories to mount  | Depends on the chosen software stack |
| `profile::cvmfs::client::alien_cache_repositories`| Array[String] | List of CVMFS repositories that need an alien cache | `[]` |
| `profile::cvmfs::client::lmod_default_modules`   | Array[String] | List of lmod default modules | Depends on the chosen software stack |
| `profile::cvmfs::local_user::cvmfs_uid`     | Integer   |  cvmfs user id  	   | 13000004  |
| `profile::cvmfs::local_user::cvmfs_gid`     | Integer   |  cvmfs group id  	   |  8000131 |
| `profile::cvmfs::local_user::cvmfs_group`   | String    |  cvmfs group name   |  'cvmfs-reserved' |
| `profile::cvmfs::alien_cache::alien_fs_root`| String | Shared file system where the alien cache will be created | `/scratch` |
| `profile::cvmfs::alien_cache::alien_folder_name`| String | Alien cache folder name | `cvmfs_alien_cache` |


## profile::fail2ban

| Variable                                      | Type                       | Description                                                                    | Default   |
| --------------------------------------------- | :------------------------- | :----------------------------------------------------------------------------- | --------- |
| `fail2ban::ignoreip`                          | Array[String]              | List of IP addresses that can never be banned (compatible with CIDR notation)  | `[]`      |
| `fail2ban::service_ensure`                    | Enum['running', 'stopped'] | Enable fail2ban service                                                        | `running` |


## profile::freeipa

| Variable | Type | Description | Default |
| -------- | :--  | :---------- | ------- |
| `profile::freeipa::base::domain_name` | String  | FreeIPA primary domain | |
| `profile::freeipa::client::server_ip` | String  | FreeIPA server ip address | |
| `profile::freeipa::mokey::port` | Integer | Mokey internal web server port | `12345`  |
| `profile::freeipa::mokey::enable_user_signup` | Boolean | Allow users to create an account on the cluster | `true` |
| `profile::freeipa::mokey::password`| String  | Password of Mokey table in MariaDB | |
| `profile::freeipa::mokey::require_verify_admin` | Boolean | Require a FreeIPA to enable Mokey created account before usage | `true` |
| `profile::freeipa::server::admin_password`| String  | Password of the FreeIPA admin account | |
| `profile::freeipa::server::ds_password`| String  | Password of the directory server | |
| `profile::freeipa::server::hbac_services`| Array[String]  | Name of services to control with HBAC rules | `['sshd', 'jupyterhub-login']` |

## profile::jupyterhub

| Variable | Type | Description | Default |
| -------- | :--  | :---------- | ------- |
| `profile::jupyterhub::hub::register_url` | String | URL to web page for user to register. Empty string removes the link on the hub login page. | "https://mokey.${domain_name}/auth/signup" |
| `profile::jupyterhub::hub::reset_pw_url` | String | URL to web page for users to reset password. Empty string removes the link on the hub login page. | "https://mokey.${domain_name}/auth/forgotpw" |

## profile::nfs

| Variable                           | Type   | Description                            | Default  |
| ---------------------------------- | :----- | :------------------------------------- | -------- |
| `profile::nfs::client::server_ip`  | String | IP address of the NFS server           | `undef`  |
| `profile::nfs::server::devices`  | Variant[String, Hash[String, Array[String]]] | Mapping between NFS share and devices to export. Generated automatically with Terraform data |  |

## profile::reverse_proxy

| Variable                                       | Type   | Description                                                             | Default   |
| ---------------------------------------------- | :----- | :---------------------------------------------------------------------- | --------- |
| `profile::reverse_proxy::domain_name`          | String | Domain name corresponding to the main DNS record A registered           |           |
| `profile::reverse_proxy::main2sub_redir` | String | Subdomain to which user should be redirected when hitting domain name directly. Empty string means no redirection | `'jupyter'` |
| `profile::reverse_proxy::subdomains` | Hash[String, String] | Subdomain names used to create vhosts to arbitrary http endpoints in the cluster| `{"ipa": "ipa.int.${domain_name}", "mokey": "${mokey_ip}:${mokey_port}", "jupyter":"https://127.0.0.1:8000"}` |

## profile::slurm

| Variable                              | Type    | Description                                                             | Default  |
| ------------------------------------- | :------ | :---------------------------------------------------------------------- | -------- |
| `profile::slurm::base::cluster_name`  | String  | Name of the cluster                                                     |          |
| `profile::slurm::base::munge_key`     | String  | Base64 encoded Munge key                                                |          |
| `profile::slurm::base::slurm_version`  | Enum[20.11, 21.08, 22.05]  | Slurm version to install                            | 21.08    |
| `profile::slurm::base::os_reserved_memory`  | Integer  | Quantity of memory in MB reserved for the operating system on the compute nodes | 512 |
| `profile::slurm::base::suspend_time`  | Integer  | Nodes becomes eligible for suspension after being idle for this number of seconds. | 3600 |
| `profile::slurm::base::resume_timeout`  | Integer  | Maximum time permitted (in seconds) between when a node resume request is issued and when the node is actually available for use. | 3600 |
| `profile::slurm::base::force_slurm_in_path`  | Boolean  | When enabled, all users (local and LDAP) will have slurm binaries in their PATH | `false`   |
| `profile::slurm::base::enable_x11_forwarding`  | Boolean  | Enable Slurm's built-in X11 forwarding capabilities           | `true`   |
| `profile::slurm::accounting::password` | String  | Password used by for SlurmDBD to connect to MariaDB                    |          |
| `profile::slurm::accounting::dbd_port` | Integer | SlurmDBD service listening port                                        |          |
| `profile::slurm::controller::selinux_context` | String | SELinux context for jobs (used only with Slurm >= 21.08)         | `user_u:user_r:user_t:s0` |
| `profile::slurm::controller::tfe_token` | String | Terraform Cloud API Token. Required to enable autoscaling. | `''` |
| `profile::slurm::controller::tfe_workspace` | String | Terraform Cloud workspace id. Required to enable autoscaling. | `''` |
| `profile::slurm::controller::tfe_var_pool` | String | Named of the variable in Terraform Cloud workspace to control compute node pool | `'pool'` |

## profile::squid

| Variable                              | Type           | Description                                                                 | Default  |
| ------------------------------------- | :------------- | :-------------------------------------------------------------------------- | -------- |
| `profile::squid::port`                | Integer        | Squid service listening port                                                | 3128     |
| `profile::squid::cache_size`          | Integer        | Amount of disk space (MB) that can be used by Squid service                 | 4096     |
| `profile::squid::cvmfs_acl_regex`     | Array[String]  | List of regexes corresponding to CVMFS stratum users are allowed to access  | `['^(cvmfs-.*\.computecanada\.ca)$', '^(.*-cvmfs\.openhtc\.io)$', '^(cvmfs-.*\.genap\.ca)$']`     |

## profile::sssd

| Variable | Type | Description | Default  |
| -------- | :--- | :---------- | -------- |
| `profile::sssd::domains` | Hash | Dictionary of domain-config which can authenticate on the cluster | `{}` |
| `profile::sssd::access_tags` | Array[String] | List of host tags that domain user can connect to | `['login', 'node']` |
| `profile::sssd::deny_access` | Optional[Boolean] | Deny access to the domains on the host including this class, if undef, the access is defined by tags. | `undef` |


## profile::users

| Variable                              | Type           | Description                                                                 | Default  |
| ------------------------------------- | :------------- | :-------------------------------------------------------------------------- | -------- |
| `profile::users::ldap::users` | Hash[Hash] | Dictionary of users to be created in LDAP | |
| `profile::users::ldap::access_tags` | Array[String] | List of string of the form `'tag:service'` that LDAP user can connect to  | `['login:sshd', 'node:sshd', 'proxy:jupyterhub-login']` |
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

By default, Puppet will manage the LDAP user(s) password and change it in ldap if it no
longer corresponds to what is prescribed in the hieradata. To disable this feature, add
`manage_password: false` to the user(s) definition.

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
