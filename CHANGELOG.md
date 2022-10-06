# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [12.0.0] UNRELEASED

### Added

- [account] Added rsync package installation (package was missing from some base image)
- [account] Added unique filter on username when creating accounts
- [base] Added magic-castle-release file in `/etc` (PR #208)
- [base] Added generation of `/etc/hosts` from `terraform_data.yaml` information for compute nodes (PR #208)
- [base] Added definition of /etc/ssh/ssh_known_hosts for compute node (PR #208)
- [base] Added a script `prepare4image.sh` that prepare an instance to be snapshot. (PR #208)
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

