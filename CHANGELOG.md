# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [14.3.0] UNRELEASED

### Added
- Added parameters to define suspend and resume rates in Slurm (PR #421)
- Added dependency on kmod::load for nvidia-mig-parted apply (PR #422)
- Added annotations using `rake test` results (PR #423)
- Added bootstrap tag to profile::vector
- Added an alias for sudoer account to display eyaml bootstrap values (PR #426)
- Added a default robots.txt that disallows indexing of reverse proxy subdomains (PR #427)
- Added puppet metrics to Prometheus using puppet reporter (PR #434)
- Added 25.05 to list of available slurm versions

### Changed
- Declaration of physical_volume is now ignored if device isn't found
- Fixed munge systemd service file (PR #431)
- Bumped puppet-jupyterhub to 6.8.1
- Made prometheus related services virtual puppet resources (PR #432)
- Moved require Tcp_conn_validator['consul'] to profile::consul (PR #435)
- Improved integration Slurm prometheus exporter (PR #436)
- Made sure all services using them are stopped before GPU drivers are unloaded (PR #438)
- Fixed issues that prevents mgmt and nfs tags to be greater than 1 (PR #440)
- Bumped slurm to 24.11 (#419)
- Fixed iptables missing /run/lock/subsys (PR #444)

## [14.2.1] 2025-02-21

### Changed
- Bumped Slurm Terraform Cloud autoscaler to 0.6.1
- Bumped puppet-jupyterhub to 6.8.1

## [14.2.0] 2025-02-20

### Added

- Added a check on hostname length before calling ipa-client-install (PR #403)
- Added an epel dependency on package slurm
- Defined restart for httpd in FreeIPA
- Added include sssd::client in freeipa::server
- Added option to define custom weight for nodes in slurm (PR #410)
- Added option to define mkfs_options for volumes (PR #408)
- Added option to restrict NVIDIA profiling (PR #413)
- Added a parameter to grant groups ssh access to compute nodes (PR #350)
- Add support for NVIDIA Grid VGPU in Azure (PR #411)

### Changed

- Replaced ipa commands by batch python script with ipa console (PR #404)
- Replaced mokey user by mokey service
- Replaced dns records wait_for by just ipa_https
- Configured internal domain as ipa_domain in only in common.yaml
- Replaced consul template for slurm.conf by Puppet function + Terraform data (PR #401)
- Replaced "include consul" by "include profile::consul" in `software_stack`
- Bumped puppet-jupyterhub to 6.8.0
- Refactored volumes definition (PR #412)
- Moved authentication methods to its own sshd config file (PR #416)
- Generalized local_user to make more parameters parametrizable (PR #312)

### Removed

- Removed munge's epel yumrepo requirement (PR #402)
- Droped support for ext3 (PR #412)

## [14.1.3] 2025-01-29

No changes to Puppet code.

Refer to [magic_castle changelog](https://github.com/ComputeCanada/magic_castle/blob/main/CHANGELOG.md)

## [14.1.2] 2024-11-19

No changes to Puppet code.

Refer to [magic_castle changelog](https://github.com/ComputeCanada/magic_castle/blob/main/CHANGELOG.md)

## [14.1.1] 2024-11-19

No changes to Puppet code.

Refer to [magic_castle changelog](https://github.com/ComputeCanada/magic_castle/blob/main/CHANGELOG.md)

## [14.1.0] 2024-11-17

### Added

- Added a dependency to ipa-install-client exec on resources that takes most of the configuration time.
This levels the configuration time of instances resulting in the cluster configuration time corresponds
to the management instance configuration time.

## [14.0.0] 2024-11-12

### Added

- Added ability to define gieradata per instances group (PR #324)
- Added option to disable CVMFS_STRICT_MOUNT (PR #335)
- Added option to install additional OS packages (PR #290)
- Added enable_scrontab to slurm::base (PR #329)
- Added support for vector.dev (PR #356)
- Added user quota support with XFS (PR #308)
- Added puppet-forge's rsyslog (PR #321)
- Added support for Slurm 23.11 (PR #359)
- Added support for Slurm 24.05 (PR #364)
- Added perl-Sys-hostname in base slurm when os major >= 9 (PR #366)
- Added option to disable Slurm's spank plugin to manage tmpfs mounts (PR #337)
- Added authenticationmethods param to local user (PR #340)
- Added option for user to specify CephFS version (PR #380)
- Provided JupyterHub the ability to create users in FreeIPA (PR #397)

### Changed

- Fixed issue #351 - "prepare4image.sh fails to run to completion..." (PR #352)
- Generalized ceph.pp to allow multiple cephfs mounting (PR #313)
- Adjusted user limits on compute node (PR #311)
- Refactored NFS server and client to allow running nfs and mgmt on distinct instances (PR #300)
- Improved prepare4image.sh handling of mounted volumes (#338)
- Added firewall definition to bootstrap
- Made profile::sssd module works on its own with or without profile::freeipa (PR #330)
- Replaced file_line by sshd_config provider for UseDNS and HostbasedAuthentication (PR #367)
- Fixed Arbutus vgpu rpm src (PR #369)
- Changed Nvidia driver source to stream - proprietary version (PR #373)
- Made prepare4image.sh remove only puppet data cache directories
- Replaced nvidia-persistenced user by dynamic systemd user (PR #383)
- Bumped nvidia driver to v550-dkms
- Upgraded default Compute Canada environment to StdEnv/2023 (PR #390)
- Bumped puppet-jupyterhub to 6.3.0

### Removed

- Removed branching related to CentOS 7 (PR #358)
- Pruned slurm versions no longer supported by SchedMD (PR #365)

## [13.5.0] 2024-04-11

### Added

- Support for NVIDIA MIG (PR #276)
- Support for AWS EFA (PR #331)

### Changed

- Bumped Slurm version to 23.02 (PR #276)

### Removed

- Removed support for Slurm 20.11 (PR #276)

## [13.4.0] 2024-04-09

### Added
- Added class `software_stack` (PR #304)
- Enabled Prometheus alertmanager for mgmt (PR #318)
- Added support for ssh authorized keys options (PR #344)

### Changed

- Moved software stack content out of cvmfs class into its own class (PR #304)
- Fixed cvmfs configuration order in Puppet (PR #310)
- Improved error handling in mkhome and mkproject daemon by implementing pipeline with shell fifo (PR #328)
- Improved mkproject daemon handling of error and of group locking (PR #346)

### Removed

- Remove profile::mfa::provider from common.yaml

## [13.3.2] 2024-02-19

### Changed
- Bumped puppet-jupyterhub to 5.0.4

## [13.3.1] 2024-01-17

### Changed
- Moved Default=YES from PartitionName=DEFAULT to PartitionName=cpubase_by_core1 in slurm.conf

## [13.3.0] 2024-01-15

### Changed
- Update EESSI for software.eessi.io (#294)
- Moved default partition parameters to DEFAULT

### Added
- Added a parameter to configure slurm.conf addendum (#257)
- Defined a value for ReturnToService in slurm.conf (#288)
- Defined a value for ResumeFailProgram in slurm.conf (#291)
- Defined PrivateData=cloud in slurm.conf for Slurm < 23.02 (#293)

### Removed

- Removed scontrol_update_state resource from profile::slurm::node

## [13.2.1] 2024-01-12

No changes to Puppet code.

Refer to [magic_castle changelog](https://github.com/ComputeCanada/magic_castle/blob/main/CHANGELOG.md)

## [13.2.0] 2024-01-09

### Added

- Added support for FreeIPA automembership rule (#287)

### Changed

- Bumped Slurm autoscale TFE version to 0.5.1 (#296)
- Changed default MOTD to an empty string
- Moved mkhome and mkproject logic to bash function (#287)

## [13.1.0] 2023-10-27

### Added

- Added ability to define login node MOTD using puppetlabs-motd

### Changed

- Moved mkhome and mkscratch logic in bash functions.
- Removed infinite while loop in mhome (#281)
- File `/etc/hosts` is now generated from a template instead of appending hosts (#282)
- prepare4image.sh now removes cluster specific content from /etc/hosts (#277)

## [13.0.0] 2023-10-13

### Added

- Added selinux module for Caddy read access to somaxconn
- Added resource collectors to define requirements for service `slurmd`. The resource
collector requirements only apply if their corresponding class is included in the site
definition.
- Added `include mysql::server`` in classes that needs a MySQL server.
- Added missing sssd service include to jupyterhub::hub
- Added include epel in fail2ban and ceph
- Added include profile::gpu in profile::slurm::node
- Added include epel to slurm::base
- Added ensurance /etc/ssh/ssh_known_hosts exists
- Added require Class['consul::reload_service'] to wait_for slurmctld host
- Added missing include consul_template in cvmfs.pp
- Added ability to add extra environment variables to CVMFS site.sh
- Added ability for user to shuffle module include in site.yaml (`magic_castle::site::enable_chaos`)
- Added support for Rocky / Alma Linux 9

### Changed

- Refactored `profile::reverse_proxy` to allow arbitrary subdomain and proxy definition
- Replaced `require profile::accounts` by resource collection in `ldap_users`
- Replaced bootstrap.sh puppet command by application of all resources tagged as `mc_bootstrap`
- Replaced require by resource collector in profile::accounts
- Moved `mysql::server` out of `slurm::accounting` and in hieradata
- Redirected output of ipa-client-uninstall_bad-hostname onlyif curl command to /dev/null
- Udpated fail2ban module to 4.2.0
- Moved swap file defintion from profile::base to common.yaml
- Moved xauth from profile::base to profile::slurm::base
- Moved puppet cache mode change from profile::base to profile::consul::puppet_watch
- Moved ssh config and ssh_known_hosts from profile::base to their own classes
- Moved consul_template from profile::base to profile::consul
- Merged profile::consul::server and profile::consul::client classes
- Moved CentOS powertools repo enabling to its own class
- Moved /etc/hosts definition to its own class
- Moved sssd service to its own class
- Replaced site.pp by site.yaml
- Fixed sed_fqdn onlyif
- Replaced sed_host_puppet by sed_host_wo_fqdn
- Fixed key used slurm_compute_weights to retrieve instances' memory ('ram' instead of 'realmemory')
- Bumped slurm-autoscale-tfe version to v0.4.0
- Improved prepare4image.sh script (#256)

### Removed
- Removed service clean-nfs-rbind
- Removed class profile::mfa
- Removed `require profile::base` from profile::nfs::server
- Disabled unused epel repos
- Removed profile::nfs exec `exportfs -ua; cat...; exportfs -a`
- Removed puppet alias from etc/hosts

## [12.6.7] 2023-09-29

### Changed
- Fixed VGPU identification facts when dealing with NVIDIA A100 and more than one gpus. (#268)

## [12.6.6] 2023-09-29

### Changed
- Fixed Compute Canada CVMFS rpm package name and source.

## [12.6.5] 2023-09-22

### Changed
- Fix regression introduced in #263

## [12.6.4] 2023-09-22

### Added
- Added a `fail()` call if `computecanada` is being initialized on an instance with a non `x86-64` CPU.

### Changed
- Moved cvmfs.pp code related to `RSNT_ARCH` under if `computecanada` branch.

## [12.6.3] 2023-09-22

### Changed
- Bumped cmdntrf-consul_template to v2.3.5 to support aarch64
- Fixed issue with CVMFS configuration when there are no `/scratch` NFS export (#262)

## [12.6.2] 2023-09-21

### Changed
- Updated puppetlabs-mysql to 13.3.0 (#261)

## [12.6.1] 2023-09-11

### Changed
- Fix `slurm_compute_weights` sort on ram instead of realmemory

## [12.6.0] 2023-06-29

### Added
- Added GPU monitoring with Prometheus and improve global compute node monitoring configuration (#237)
- Added `2` as a possible return code when creating HBAC rules
- Add definition `seluser` to alien cache folder.

### Changed
- Updated consul to 1.15 (#245)
- Enabled multi-servers consul configuration (#245)
- Moved from puppet facts to Terraform data to identify the ethernet interface connected to the local network. (#247)
- Bumped puppet-jupyterhub to v4.6.4


## [12.5.0] 2025-06-06

### Added
- Added support  Add support for CVMFS alien cache (#204)

### Changed
- Removed hardcoding of python 3.6 for slurm autoscale virtualenv

## [12.4.0] 2023-05-04

### Added
- Added automembership rule for users who self sign-up with Mokey
- Added HBAC rules to allow self signup user to connect

### Changed
- Defined missing variable `$cidr` in `profile::nfs::server::export_volume`.
- Added a before `Package['cvmfs']` clause for `cvmfs` user and `cvmfs-reserved` group.
- Changed the default FreeIPA user shell from `/bin/sh` to `/bin/bash`.
- Bumped puppet-jupyterhub to v4.6.1

## [12.3.0] 2023-02-22

### Changed
- Fixed mkhome daemon to retry initial rsync of a LDAP user's home (#218, #219)
- Fixed LDAP TLS certificate to add ipa subdomain (#215)
- Moved `consul_template::watch` of `slurm-consul.conf` in `slurm::base` (#221, #222)
- Consolidated generation of `/etc/hosts` in a single class `profile::base` (#221, #225)

### Added
- Activated SSH hostbased authentication on compute nodes, from login and compute nodes. (#5, #217)
- Added automatic generation of HBAC rules for LDAP users based on instance tags (#221, #225)
- Added a mount bind of NFS exports on the NFS server if the LDAP users can connect to it (#221, #224)
- Add mising profile:slurm::submitter class to profile::jupyterhub::hub (#227, #230)
- Added creation of Slurm partitions based on the compute node hostname prefixes(#38, #226)

### Removed
- Removed Singularity class. `apptainer` is now provided by CVMFS. (#216)

## [12.2.0] 2023-02-02


### Changed
- Bump puppet-jupyterhub to 4.5.0

## [12.1.0] 2023-01-17

### Added
- Added eyaml lookup in hiera.yaml
- Added generation of ipa admin password to bootstrap.sh
- Added resource allowing reset of ipa admin password
- Added generation of consul token, freeipa admin password, mysql password, munge token to bootstrap script
- Defined a specific password for directory server
- Added a specific password for slurmdbd
- Added management of LDAP user password in Puppet - guest password can now be resetted by changing the hieradata
- Added documentation

### Changed
- Replaced mokey password lookup by class variable

### Removed

## [12.0.0] 2023-01-16

### Added

- [account] Added rsync package installation (package was missing from some base image)
- [account] Added unique filter on username when creating accounts
- [base] Added magic-castle-release file in `/etc` (PR #208)
- [base] Added generation of `/etc/hosts` from `terraform_data.yaml` information for compute nodes (PR #208)
- [base] Added definition of /etc/ssh/ssh_known_hosts for compute node (PR #208)
- [base] Added a script `prepare4image.sh` that prepare an instance to be snapshot. (PR #208)
- [cvmfs] Added cvmfs local user
- [singularity] Added singularity to the list of EPEL exclusion
- [slurm] Added definition of `node.conf` using `terraform_data.yaml` information (PR #208)
- [slurm] Added ResumeProgram and SuspendProgram option allowing Slurm to autoscale with Terraform Cloud (PR #208)
- [slurm] Added virtual environment and installation of Slurm TFE autoscale Python package (PR #208)
- [slurm] Added new file `/etc/slurm/env.secrets` containing environment variable to interact with TFE (PR #208)
- [slurm] Added version to slurm and slurmdbd package name installation


### Changed

- [consul] Added timestamp payload support in `puppet_event_handler` and improved logic
- [cvmfs] Updated source of cvmfs-repo
- [freeipa] Moved `kinit_wrapper` creation to `freeipa::server` (PR #208)
- [gpu] Improved GPU driver symlink creation to avoid creating invalid symlinks on first Puppet run (PR #209)
- [gpu] Fixed nvidia-persistenced /var/run folder
- [nfs] Fixed volume pool to keep only unique volumes
- [puppetfile] Bumped puppet-jupyterhub version to v4.3.6
- [slurm] Moved node weight computation from a consul plugin to a Puppet function (PR #208)
- [slurm] Simplified COPR slurm yumrepo definition (PR #208)
- [slurm] Moved definition of `gres.conf` from node to base (PR #208)
- [slurm] Fixed slurmdbd regex (PR #208)
- [slurm] Fixed source of spank-cc-tmpfs_mount for Slurm 22.05 (PR #208)
- [slurm] Configured default state of compute node to CLOUD

### Removed

- [base] Removed magic castle plugin rpm install
- [base] Removed owner and group definition in `/var/puppet/cache`
- [base] Removed ssh-rsa from HostKeyAlgorithms and PubkeyAcceptedKeyTypes
- [freeipa] Removed PTR record creation from `freeipa::client`
- [gpu] Removed nvidia_driver_version fact (PR #209)
- [slurm] Removed consul-template generation of node.conf (PR #208)
- [slurm] Removed support for Slurm 19.08 (PR #208)
- [slurm] Dropped NVML usage in gres.conf (incompatible with cloud state node) (PR #208)
- [slurm] Removed NVML enabled Slurm yum repo

