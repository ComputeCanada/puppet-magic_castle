# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [12.3.0] UNRELEASED

### Changed
- Fixed mkhome daemon to retry initial rsync of a LDAP user's home (#218, #219)
- Fixed LDAP TLS certificate to add ipa subdomain (#215)
- Moved `consul_template::watch` of `slurm-consul.conf` in `slurm::base` (#221, #222)
- Consolidated generation of `/etc/hosts` in a single class `profile::base` (#221, #225)

### Added
- Activated SSH hostbased authentication on compute nodes, from login and compute nodes. (#5, #217)
- Added automatic generation of HBAC rules for LDAP users based on instance tags (#221, #225)
- Added a mount bind of NFS exports on the NFS server if the LDAP users can connect to it (#221, #224)

### Removed
- Removed Singulairty class. `apptainer` is now provided by CVMFS. (#216)

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

