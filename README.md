# Puppet Magic Castle

This repo contains the Puppet classes that are used to define the roles of the
instances in a Magic Castle cluster. The attribution of the roles is done in
`manifests/site.pp`. The functioning of the profile classes can be customized
by defined values in the hieradata. The following sections list the available
variables for each profile.

## profile::base

| Variable                         | Type   | Description                                                             | Default  |
| -------------------------------- | :----- | :---------------------------------------------------------------------- | -------- |
| `profile::base::email`           | String | Email address that will receive puppet logs for runs with changes       | `undef`  |
| `profile::base::sudoer_username` | String | Name of the user with sudo rights. Used to config SELinux user mapping  | `'centos'` |

## profile::consul

| Variable                       | Type   | Description                                                             | Default  |
| ------------------------------ | :----- | :---------------------------------------------------------------------- | -------- |
| `profile::consul::server_ip`   | String | IP address of the consul server                                         |          |

## profile::cvmfs

| Variable                                         | Type          | Description                                         | Default                         |
| ------------------------------------------------ | :------------ | :-------------------------------------------------- | ------------------------------- |
| `profile::cvmfs::client::lmod_default_modules`   | Array[String] | List of lmod default modules                        | `['nixpkgs/16.09', 'imkl/2018.3.222', 'gcc/7.3.0', 'openmpi/3.1.2']` |
| `profile::cvmfs::client::extra_repos`            | Array[String] | List of extra CVMFS Repos to add to the system      | `[]` |


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
| `profile::freeipa::guest_accounts::guest_passwd` | String  | Password set for all guest accounts                                                 |          |
| `profile::freeipa::guest_accounts::nb_accounts`  | Integer | Number of guests account that needs to be created                                   |          |
| `profile::freeipa::guest_accounts::prefix`       | String  | Prefix used to identified guest accounts followed by their index i.e: `user12`      | `'user'` |


## profile::globus

| Variable                           | Type   | Description                                                             | Default  |
| ---------------------------------- | :----- | :---------------------------------------------------------------------- | -------- |
| `profile::globus::globus_user`     | String | Username under which the globus endpoint will be registered.            | `undef`  |
| `profile::globus::globus_password` | String | Password associated with the globus username.                           | `undef`  |

## profile::nfs

| Variable                           | Type   | Description                            | Default  |
| ---------------------------------- | :----- | :------------------------------------- | -------- |
| `profile::nfs::client::server_ip`  | String | IP address of the NFS server           | `undef`  |


## profile::reverse_proxy

| Variable                              | Type   | Description                                                             | Default  |
| ------------------------------------- | :----- | :---------------------------------------------------------------------- | -------- |
| `profile::reverse_proxy::domain_name` | String | Domain name corresponding to the main DNS record A registered           |          |

## profile::slurm

| Variable                              | Type    | Description                                                             | Default  |
| ------------------------------------- | :------ | :---------------------------------------------------------------------- | -------- |
| `profile::slurm::base::cluster_name`  | String  | Name of the cluster                                                     |          |
| `profile::slurm::base::munge_key`     | String  | Base64 encoded Munge key                                                |          |
| `profile::slurm::accounting:password` | String  | Password used by for SlurmDBD to connect to MariaDB                     |          |
| `profile::slurm::accounting:dbd_port` | Integer | SlurmDBD service listening port                                         |          |

## profile::squid

| Variable                              | Type     | Description                                                             | Default  |
| ------------------------------------- | :------- | :---------------------------------------------------------------------- | -------- |
| `profile::squid::port`                | Integer  | Squid service listening port                                            | 3128     |

## profile::workshop

| Variable                          | Type   | Description                                                                     | Default                  |
| --------------------------------- | :----- | :------------------------------------------------------------------------------ | ------------------------ |
| `profile::workshop::userzip_url`  | String | URL pointing to a zip that needs to be extracted in each guest account's home   | `''`                     |
| `profile::workshop::userzip_path` | String | Path on the nfs server where to save the userzip archive                        | `'/project/userzip.zip'` |
