# Puppet Magic Castle

This repo contains the Puppet classes that are used to define the roles of the
instances in a Magic Castle cluster. The attribution of the roles is done in
`manifests/site.pp`. The functioning of the profile classes can be customized
by defined values in the hieradata. The following sections list the available
variables for each profile.

To improve readability, only the class' variable names appear in the "Variable" column.
To configure the variable in hieradata, make sure to prepend it corresponding class name
as a prefix. The class names correspond to the section name. For example, to define the
`project_regex` of `profile::accounts`, you will have to add the following to your hieradata:
```yaml
profile::accounts::project_regex: '(users-[0-9]*)'
```

## magic_castle::site

### parameters

| Variable        | Description                                                                            | Type                |
| :-------------- | :------------------------------------------------------------------------------------- | :-----------------  |
| `all`           | List of classes that are included by all instances                                     | Array[String]       |
| `tags`          | Mapping tag-classes - instances that **have** the tag include the classes              | Hash[Array[String]] |
| `not_tags`      | Mapping tag-classes - instances that **do not have** the tag include the classes       | Hash[Array[String]] |
| `enable_chaos`  | Shuffle class inclusion order - used for debugging purposes                            | Boolean             |

<details>
<summary>default values</summary>

```yaml
magic_castle::site::all:
  - profile::base
  - profile::consul
  - profile::users::local
  - profile::sssd::client
  - profile::metrics::node_exporter
  - swap_file
magic_castle::site::tags:
  dtn:
    - profile::globus
  login:
    - profile::fail2ban
    - profile::cvmfs::client
    - profile::slurm::submitter
    - profile::ssh::hostbased_auth::client
  mgmt:
    - mysql::server
    - profile::freeipa::server
    - profile::metrics::server
    - profile::metrics::slurm_exporter
    - profile::rsyslog::server
    - profile::squid::server
    - profile::slurm::controller
    - profile::freeipa::mokey
    - profile::slurm::accounting
    - profile::accounts
    - profile::users::ldap
  node:
    - profile::cvmfs::client
    - profile::gpu
    - profile::jupyterhub::node
    - profile::slurm::node
    - profile::ssh::hostbased_auth::client
    - profile::ssh::hostbased_auth::server
    - profile::metrics::slurm_job_exporter
  nfs:
    - profile::nfs::server
    - profile::cvmfs::alien_cache
  proxy:
    - profile::jupyterhub::hub
    - profile::reverse_proxy
magic_castle::site::not_tags:
  nfs:
    - profile::nfs::client
  mgmt:
    - profile::freeipa::client
    - profile::rsyslog::client
```
</details>

<details>
<summary>example 1: enabling CephFS client in a complete Magic Castle cluster</summary>

```yaml
magic_castle::site::tags:
  login:
    - profile::ceph::client
  node:
    - profile::ceph::client
```
</details>

<details>
<summary>example 2: barebone Slurm cluster with external LDAP authentication</summary>

```yaml
magic_castle::site::all:
  - profile::base
  - profile::consul
  - profile::sssd::client
  - profile::users::local
  - swap_file

magic_castle::site::tags:
  mgmt:
    - profile::slurm::controller
    - profile::nfs::server
  login:
    - profile::slurm::submitter
    - profile::nfs::client
  node:
    - profile::slurm::node
    - profile::nfs::client
    - profile::gpu

magic_castle::site::not_tags: {}
```

</details>

## profile::accounts

This class configures two services to bridge LDAP users, Slurm accounts and users' folders in filesystems. The services are:
- `mkhome`: monitor new uid entries in slapd access logs and create their corresponding /home and optionally /scratch folders.
- `mkproject`: monitor new gid entries in slapd access logs and create their corresponding /project folders and Slurm accounts if it matches the project regex.

### parameters

| Variable        | Description                                                   | Type       |
| :-------------- | :------------------------------------------------------------ | :--------  |
| `project_regex` | Regex identifying FreeIPA groups that require a corresponding Slurm account | String     |
| `skel_archives` | Archives extracted in each FreeIPA user's home when created | Array[Struct[{filename => String[1], source => String[1]}]] |

<details>
<summary>default values</summary>

```yaml
profile::accounts::project_regex: '(ctb\|def\|rpp\|rrg)-[a-z0-9_-]*'
profile::accounts::skel_archives: []
```
</details>

<details>
<summary>example</summary>

```yaml
profile::accounts::project_regex: '(slurm)-[a-z0-9_-]*'
profile::accounts::skel_archives:
  - filename: hss-programing-lab-2022.zip
    source: https://github.com/ComputeCanada/hss-programing-lab-2022/archive/refs/heads/main.zip
  - filename: hss-training-topic-modeling.tar.gz
    source: https://github.com/ComputeCanada/hss-training-topic-modeling/archive/refs/heads/main.tar.gz
```
</details>

### optional dependencies
This class works at its full potential if these classes are also included:
- [`profile::freeipa::server`](#profilefreeipaserver)
- [`profile::nfs::server`](#profilenfsserver)
- [`profile::slurm::base`](#profileslurmbase)

## profile::base

This class install packages, creates files and install services that have yet
justified the creation of a class of their own but are very useful to Magic Castle
cluster operations.

### parameters

| Variable       | Description                                                                            | Type   |
| :------------- | :------------------------------------------------------------------------------------- | :----- |
| `version`      | Current version number of Magic Castle                                                 | String |
| `admin_email`  | Email of the cluster administrator, use to send log and report cluster related issues  | String |

<details>
<summary>default values</summary>

```yaml
profile::base::version: '13.0.0'
profile::base::admin_emain: ~ #undef
```
</details>

<details>
<summary>example</summary>

```yaml
profile::base::version: '13.0.0-rc.2'
profile::base::admin_emain: "you@email.com"
```
</details>

### inclusion

When `profile::base` is included, these classes are automatically included too:
- [`puppet-epel`](https://forge.puppet.com/modules/puppet/epel/readme)
- [`puppet-selinux`](https://forge.puppet.com/modules/puppet/selinux/readme)
- [`puppetlabs-stdlib`](https://forge.puppet.com/modules/puppetlabs/stdlib/readme)
- [`profile::base::azure`](#profilebaseazure) (only when running in Microsoft Azure Cloud)
- [`profile::base::etc_hosts`](#profilebaseetc_hosts)
- [`profile::base::powertools`](#profilebasepowertools)
- `profile::ssh::base`
- `profile::mail::server` (when parameter `admin_email` is defined)

## profile::base::azure

This class ensures Microsoft Azure Linux Guest Agent is not installed as it tends to interfere
with Magic Castle configuration. The class also install Azure udev storage rules that would
normally be provided by the Linux Guest Agent.

### parameters

None

## profile::base::etc_hosts

This class ensures that each instance declared in Magic Castle `main.tf` have an entry
in `/etc/hosts`. The ip addresses, fqdns and short hostnames are taken from the `terraform.instances`
datastructure provided by `/etc/puppetlabs/data/terraform_data.yaml`.

### parameters

None

## profile::base::powertools

This class ensures the DNF Powertools repo is enabled when using EL8. For all other EL versions, this
class does nothing.

### parameters

None

## profile::ceph::client

### parameters

| Variable                     | Description                                                 | Type          |
| :--------------------------- | :---------------------------------------------------------- | ------------- |
| `share_name`                 | CEPH share name                                             | String        |
| `access_key`                 | CEPH share access key                                       | String        |
| `export_path`                | Path of the share as exported by the monitors               | String        |
| `mon_host`                   | List of CEPH monitor hostnames                              | Array[String] |
| `mount_binds`                | List of CEPH share folders that will bind mounted under `/` | Array[String] |
| `mount_name`                 | Name to give to the CEPH share once mounted under `/mnt`    | String        |
| `binds_fcontext_equivalence` | SELinux file context equivalence for the CEPH share         | String        |

<details>
<summary>default values</summary>

```yaml
profile::ceph::client::mount_binds: []
profile::ceph::client::mount_name: 'cephfs01'
profile::ceph::client::binds_fcontext_equivalence: '/home'
```
</details>

<details>
<summary>example</summary>

```yaml
profile::ceph::client::share_name: "your-project-shared-fs"
profile::ceph::client::access_key: "MTIzNDU2Nzg5cHJvZmlsZTo6Y2VwaDo6Y2xpZW50OjphY2Nlc3Nfa2V5"
profile::ceph::client::export_path: "/volumes/_nogroup/"
profile::ceph::client::mon_host:
  - 192.168.1.3:6789
  - 192.168.2.3:6789
  - 192.168.3.3:6789
profile::ceph::client::mount_binds:
  - home
  - project
  - software
profile::ceph::client::mount_name: 'cephfs'
profile::ceph::client::binds_fcontext_equivalence: '/home'
```
</details>

## profile::consul

| Variable  | Description                         | Type          |
| --------- | :---------------------------------- | ------------- |
| `servers` | IP addresses of the consul servers  | Array[String] |

<details>
<summary>default values</summary>

```yaml
profile::consul::servers: "%{alias('terraform.tag_ip.puppet')}"
```
</details>

<details>
<summary>example</summary>

```yaml
profile::consul::servers:
  - 10.0.1.2
  - 10.0.1.3
  - 10.0.1.4
```
</details>

## profile::cvmfs

### profile::cvmfs::client

| Variable                  | Description                                    | Type        |
| :------------------------ | :--------------------------------------------- | -------------- |
| `quota_limit`             | Instance local cache directory soft quota (MB) | Integer |
| `initial_profile`         | Path to shell script initializing software stack environment variables | String |
| `extra_site_env_vars`     | Map of environment variables that will be exported before sourcing profile shell scripts. | Hash[String, String] |
| `repositories`            | List of CVMFS repositories to mount  | Array[String] |
| `alien_cache_repositories`| List of CVMFS repositories that need an alien cache | Array[String] |
| `lmod_default_modules`    | List of lmod default modules |Array[String] |

<details>
<summary>default values</summary>

```yaml
profile::cvmfs::client::quota_limit: 4096
profile::cvmfs::client::extra_site_env_vars: { }
profile::cvmfs::client::alien_cache_repositories: [ ]
```

#### computecanada software stack

```yaml
profile::cvmfs::client::repositories:
  - cvmfs-config.computecanada.ca
  - soft.computecanada.ca
profile::cvmfs::client::initial_profile: "/cvmfs/soft.computecanada.ca/config/profile/bash.sh"
profile::cvmfs::client::lmod_default_modules:
  - gentoo/2020
  - imkl/2020.1.217
  - gcc/9.3.0
  - openmpi/4.0.3
```

#### eessi software stack

```yaml
profile::cvmfs::client::repositories:
  - pilot.eessi-hpc.org
profile::cvmfs::client::initial_profile: "/cvmfs/pilot.eessi-hpc.org/latest/init/Magic_Castle/bash"
profile::cvmfs::client::lmod_default_modules:
  - GCC
```


</details>

<details>
<summary>example</summary>

```yaml
profile::cvmfs::client::quota_limit: 8192
profile::cvmfs::client::initial_profile: "/cvmfs/soft.computecanada.ca/config/profile/bash.sh"
profile::cvmfs::client::extra_site_env_vars:
  CC_CLUSTER: beluga
profile::cvmfs::client::repositories:
  - atlas.cern.ch
profile::cvmfs::client::alien_cache_repositories:
  - grid.cern.ch
profile::cvmfs::client::lmod_default_modules:
  - gentoo/2020
  - imkl/2020.1.217
  - gcc/9.3.0
  - openmpi/4.0.3
```
</details>

### profile::cvmfs::local_user

| Variable      | Type    | Description      | Default          |
| ------------- | :------ | :--------------- | ---------------- |
| `cvmfs_uid`   | Integer | cvmfs user id  	 | 13000004         |
| `cvmfs_gid`   | Integer | cvmfs group id   | 8000131          |
| `cvmfs_group` | String  | cvmfs group name | 'cvmfs-reserved' |

<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

### profile::cvmfs::alien_cache


| Variable      | Type    | Description      | Default          |
| ------------- | :------ | :--------------- | ---------------- |
| `alien_fs_root`    | String | Shared file system where the alien cache will be created | `/scratch`          |
| `alien_folder_name`| String | Alien cache folder name                                  | `cvmfs_alien_cache` |

<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

## profile::fail2ban

| Variable      | Type    | Description      | Default          |
| ------------- | :------ | :--------------- | ---------------- |
| `ignoreip`        | Array[String]              | List of IP addresses that can never be banned (compatible with CIDR notation)  | `[]`      |
| `service_ensure`  | Enum['running', 'stopped'] | Enable fail2ban service                                                        | `running` |

<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

## profile::freeipa

### profile::freeipa::base

| Variable      | Type    | Description      | Default          |
| ------------- | :------ | :--------------- | ---------------- |
| `domain_name` | String  | FreeIPA primary domain | |

<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

### profile::freeipa::client

| Variable      | Type    | Description      | Default          |
| ------------- | :------ | :--------------- | ---------------- |
| `server_ip` | String  | FreeIPA server ip address | |

<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

### profile::freeipa::mokey

| Variable      | Type    | Description      | Default          |
| ------------- | :------ | :--------------- | ---------------- |
| `port` | Integer | Mokey internal web server port | `12345`  |
| `enable_user_signup` | Boolean | Allow users to create an account on the cluster | `true` |
| `password`| String  | Password of Mokey table in MariaDB | |
| `require_verify_admin` | Boolean | Require a FreeIPA to enable Mokey created account before usage | `true` |

<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

### profile::freeipa::server

| Variable      | Type    | Description      | Default          |
| ------------- | :------ | :--------------- | ---------------- |
| `admin_password`| String  | Password of the FreeIPA admin account | |
| `ds_password`| String  | Password of the directory server | |
| `hbac_services`| Array[String]  | Name of services to control with HBAC rules | `['sshd', 'jupyterhub-login']` |

<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

## profile::jupyterhub

### profile::jupyterhub::hub

| Variable      | Type    | Description      | Default          |
| ------------- | :------ | :--------------- | ---------------- |
| `register_url` | String | URL to web page for user to register. Empty string removes the link on the hub login page. | "https://mokey.${domain_name}/auth/signup" |
| `reset_pw_url` | String | URL to web page for users to reset password. Empty string removes the link on the hub login page. | "https://mokey.${domain_name}/auth/forgotpw" |

<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

## profile::nfs

### profile::nfs::client

| Variable      | Type    | Description      | Default          |
| ------------- | :------ | :--------------- | ---------------- |
| `server_ip`  | String | IP address of the NFS server           | `undef`  |

### profile::nfs::server
| Variable      | Type    | Description      | Default          |
| ------------- | :------ | :--------------- | ---------------- |
| `devices`  | Variant[String, Hash[String, Array[String]]] | Mapping between NFS share and devices to export. Generated automatically with Terraform data |  |


<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

## profile::reverse_proxy

| Variable                                       | Type   | Description                                                             | Default   |
| ---------------------------------------------- | :----- | :---------------------------------------------------------------------- | --------- |
| `domain_name`          | String | Domain name corresponding to the main DNS record A registered           |           |
| `main2sub_redir` | String | Subdomain to which user should be redirected when hitting domain name directly. Empty string means no redirection | `'jupyter'` |
| `subdomains` | Hash[String, String] | Subdomain names used to create vhosts to arbitrary http endpoints in the cluster| `{"ipa": "ipa.int.${domain_name}", "mokey": "${mokey_ip}:${mokey_port}", "jupyter":"https://127.0.0.1:8000"}` |
| `remote_ips` | Hash[String, Array[String]] | List of allowed ip addresses per subdomain. When left undefined, there are no restrictions on subdomain access. | `{}` |

<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

## profile::slurm

### profile::slurm::base

| Variable | Type    | Description | Default  |
| -------- | :------ | :---------- | -------- |
| `cluster_name` | String  | Name of the cluster | |
| `munge_key` | String  | Base64 encoded Munge key | |
| `slurm_version` | Enum[20.11, 21.08, 22.05]  | Slurm version to install | 21.08 |
| `os_reserved_memory` | Integer | Quantity of memory in MB reserved for the operating system on the compute nodes | 512 |
| `suspend_time` | Integer | Nodes becomes eligible for suspension after being idle for this number of seconds. | 3600 |
| `resume_timeout` | Integer | Maximum time permitted (in seconds) between when a node resume request is issued and when the node is actually available for use. | 3600 |
| `force_slurm_in_path`  | Boolean  | When enabled, all users (local and LDAP) will have slurm binaries in their PATH | `false` |
| `enable_x11_forwarding` | Boolean | Enable Slurm's built-in X11 forwarding capabilities | `true`| | |

<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

### profile::slurm::accounting

| Variable | Type    | Description | Default  |
| -------- | :------ | :---------- | -------- |
| `password` | String | Password used by for SlurmDBD to connect to MariaDB |  |
| `admins` | Array[String] | List of Slurm administrator usernames | `[]` |
| `accounts` | Hash[String, Hash] | Define Slurm account name and [specifications](https://slurm.schedmd.com/sacctmgr.html#SECTION_GENERAL-SPECIFICATIONS-FOR-ASSOCIATION-BASED-ENTITIES) | `{}` |
| `users` | Hash[String, Array[String]] | Define association between usernames and accounts | `{}` |
| `options` | Hash[String, Any] | Define additional cluster's global [Slurm accounting options](https://slurm.schedmd.com/sacctmgr.html#SECTION_GENERAL-SPECIFICATIONS-FOR-ASSOCIATION-BASED-ENTITIES) | `{}` |
| `dbd_port` | Integer | SlurmDBD service listening port | 6819 |

<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

Example of the definition of Slurm accounts and their association with users:
```yaml
profile::slurm::accounting::admins: ['oppenheimer']

profile::slurm::accounting::accounts:
  physics:
    Fairshare: 1
    MaxJobs: 100
  engineering:
    Fairshare: 2
    MaxJobs: 200
  humanities:
    Fairshare: 1
    MaxJobs: 300

profile::slurm::accounting::users:
  oppenheimer: ['physics']
  rutherford: ['physics', 'engineering']
  sartre: ['humanities']
```

Each username in `profile::slurm::accounting::users` and `profile::slurm::accounting::admins` have to correspond
to an LDAP or a local users. Refer to [profile::users::ldap::users](#profileusersldapusers) and
[profile::users::local::users](#profileuserslocalusers) for more information.

### profile::slurm::controller

| Variable | Type    | Description | Default  |
| -------- | :------ | :---------- | -------- |
| `selinux_context` | String | SELinux context for jobs (used only with Slurm >= 21.08) | `user_u:user_r:user_t:s0` |
| `tfe_token` | String | Terraform Cloud API Token. Required to enable autoscaling. | `''` |
| `tfe_workspace` | String | Terraform Cloud workspace id. Required to enable autoscaling. | `''` |
| `tfe_var_pool` | String | Named of the variable in Terraform Cloud workspace to control compute node pool | `'pool'` |

<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

## profile::squid

| Variable                              | Type           | Description                                                                 | Default  |
| ------------------------------------- | :------------- | :-------------------------------------------------------------------------- | -------- |
| `port`                | Integer        | Squid service listening port                                                | 3128     |
| `cache_size`          | Integer        | Amount of disk space (MB) that can be used by Squid service                 | 4096     |
| `cvmfs_acl_regex`     | Array[String]  | List of regexes corresponding to CVMFS stratum users are allowed to access  | `['^(cvmfs-.*\.computecanada\.ca)$', '^(.*-cvmfs\.openhtc\.io)$', '^(cvmfs-.*\.genap\.ca)$']`     |


<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

## profile::sssd

| Variable | Type | Description | Default  |
| -------- | :--- | :---------- | -------- |
| `domains` | Hash | Dictionary of domain-config which can authenticate on the cluster | `{}` |
| `access_tags` | Array[String] | List of host tags that domain user can connect to | `['login', 'node']` |
| `deny_access` | Optional[Boolean] | Deny access to the domains on the host including this class, if undef, the access is defined by tags. | `undef` |

<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

## profile::users

| Variable                              | Type           | Description                                                                 | Default  |
| ------------------------------------- | :------------- | :-------------------------------------------------------------------------- | -------- |
| `profile::users::ldap::users` | Hash[Hash] | Dictionary of users to be created in LDAP | |
| `profile::users::ldap::access_tags` | Array[String] | List of string of the form `'tag:service'` that LDAP user can connect to  | `['login:sshd', 'node:sshd', 'proxy:jupyterhub-login']` |
| `profile::users::local::users` | Hash[Hash] | Dictionary of users to be created locally | |

<details>
<summary>default values</summary>

```yaml
```
</details>

<details>
<summary>example</summary>

```yaml
```
</details>

### profile::users::ldap::users

A batch of 10 LDAP users, user01 to user10, can be defined in hieradata as:
```yaml
profile::users::ldap::users:
  user:
    count: 10
    passwd: user.password.is.easy.to.remember
    groups: ['def-sponsor00']
```

A single LDAP user can be defined as:
```yaml
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
```yaml
profile::users::local::users:
  bob:
    groups: ['group1', 'group2']
    public_keys: ['ssh-rsa...', 'ssh-dsa']
    # sudoer: false
    # selinux_user: 'unconfined_u'
    # mls_range: ''s0-s0:c0.c1023'
```
