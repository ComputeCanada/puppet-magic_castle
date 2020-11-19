class profile::cvmfs::client(
  Integer $quota_limit,
  Array[String] $repositories,
  Array[String] $lmod_default_modules,
){
  package { 'cvmfs-repo':
    ensure   => 'installed',
    provider => 'rpm',
    name     => 'cvmfs-release-2-6.noarch',
    source   => 'http://cvmrepo.web.cern.ch/cvmrepo/yum/cvmfs-release-latest.noarch.rpm'
  }

  package { 'cvmfs-eessi':
    ensure   => 'installed',
    provider => 'rpm',
    name     => 'cvmfs-config-eessi',
    source   => 'https://github.com/EESSI/filesystem-layer/releases/download/v0.2.3/cvmfs-config-eessi-0.2.3-1.noarch.rpm'
  }

  package { ['cvmfs', 'cvmfs-fuse3', 'cvmfs-config-default']:
    ensure  => 'installed',
    require => [Package['cvmfs-repo'], Package['cvmfs-eessi']]
  }


  $str = 'CVMFS_QUOTA_LIMIT=10000
        CVMFS_HTTP_PROXY="DIRECT"
        CVMFS_REPOSITORIES="cvmfs-config.eessi-hpc.org,pilot.eessi-hpc.org"
        '

  file { '/etc/cvmfs/default.local':
    ensure  => 'present',
    content => $str,
    require => Package['cvmfs'],
    mode   => '0644',
    notify => Exec["update_cvmfs"],
  }

  exec { "update_cvmfs":
    command     => "usr/bin/cvmfs_config reload",
    refreshonly => true
  }

  consul::service{ 'cvmfs':
    require => Tcp_conn_validator['consul'],
    token   => lookup('profile::consul::acl_api_token'),
    meta    => {
      arch => $facts['cpu_ext'],
    },
  }

  file { '/etc/profile.d/z-01-eessi.sh':
    ensure  => 'present',
    content => 'source /cvmfs/pilot.eessi-hpc.org/2020.10/init/bash',
  }

  package { ['python-pip']:
    ensure  => 'installed',
  }

  ensure_packages(['archspec'], {
         ensure   => present,
         provider => 'pip',
         require  => [ Package['python-pip'], ],
  })

  service { 'autofs':
    ensure    => running,
    enable    => true,
  }

  # Fix issue with BASH_ENV, SSH and lmod where
  # ssh client would get a "Permission denied" when
  # trying to connect to a server. The errors
  # results from the SELinux context type of
  # /cvmfs/soft.computecanada.ca/nix/var/nix/profiles/16.09/lmod/lmod/init/bash
  # To be authorized in the ssh context, it would need
  # to be a bin_t type, but it is a fusefs_t and since
  # CVMFS is a read-only filesystem, the context cannot be changed.
  # 'use_fusefs_home_dirs' policy fix that issue.
  selinux::boolean { 'use_fusefs_home_dirs': }

}
