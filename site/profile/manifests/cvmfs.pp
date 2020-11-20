class profile::cvmfs::client(
  Integer $quota_limit,
  String $initial_profile,
  Array[String] $repositories,
  Array[String] $lmod_default_modules,
){
  package { 'cvmfs-repo':
    ensure   => 'installed',
    provider => 'rpm',
    name     => 'cvmfs-release-2-6.noarch',
    source   => 'https://ecsft.cern.ch/dist/cvmfs/cvmfs-release/cvmfs-release-latest.noarch.rpm'
  }

  package { 'cc-cvmfs-repo':
    ensure   => 'installed',
    provider => 'rpm',
    name     => 'computecanada-release-1.0-1.noarch',
    source   => 'https://package.computecanada.ca/yum/cc-cvmfs-public/prod/RPM/computecanada-release-latest.noarch.rpm'
  }

  package { 'eessi-cvmfs':
    ensure   => 'installed',
    provider => 'rpm',
    name     => 'cvmfs-config-eessi-0.2.3-1.noarch',
    source   => 'https://github.com/EESSI/filesystem-layer/releases/download/v0.2.3/cvmfs-config-eessi-0.2.3-1.noarch.rpm'
  }

  package { ['cvmfs', 'cvmfs-config-computecanada', 'cvmfs-config-default', 'cvmfs-auto-setup']:
    ensure  => 'installed',
    require => [Package['cvmfs-repo'], Package['cc-cvmfs-repo'], Package['eessi-cvmfs']]
  }

  file { '/etc/cvmfs/default.local.ctmpl':
    ensure  => 'present',
    content => epp('profile/cvmfs/default.local', {
      'quota_limit'  => $quota_limit,
      'repositories' => $repositories,
    }),
    require => Package['cvmfs']
  }

  exec { 'init_default.local':
    command     => 'consul-template -template="/etc/cvmfs/default.local.ctmpl:/etc/cvmfs/default.local" -once',
    path        => [$consul_template::bin_dir],
    refreshonly => true,
    require     => [
      Class['consul_template::install'],
      Service['consul'],
    ],
    subscribe   => File['/etc/cvmfs/default.local.ctmpl']
  }

  consul::service{ 'cvmfs':
    require => Tcp_conn_validator['consul'],
    token   => lookup('profile::consul::acl_api_token'),
    meta    => {
      arch => $facts['cpu_ext'],
    },
  }

  file { '/etc/consul-template/z-00-rsnt_arch.sh.ctmpl':
    ensure => 'present',
    source => 'puppet:///modules/profile/cvmfs/z-00-rsnt_arch.sh.ctmpl',
  }

  file { '/etc/profile.d/z-01-site.sh':
    ensure  => 'present',
    content => epp('profile/cvmfs/z-01-site.sh', {
      'lmod_default_modules' => $lmod_default_modules,
      'initial_profile'      => $initial_profile,
    }),
  }

  consul_template::watch { 'z-00-rsnt_arch.sh':
    require     => File['/etc/consul-template/z-00-rsnt_arch.sh.ctmpl'],
    config_hash => {
      perms       => '0644',
      source      => '/etc/consul-template/z-00-rsnt_arch.sh.ctmpl',
      destination => '/etc/profile.d/z-00-rsnt_arch.sh',
      command     => '/usr/bin/true',
    }
  }

  consul_template::watch { '/etc/cvmfs/default.local':
    require     => File['/etc/cvmfs/default.local.ctmpl'],
    config_hash => {
      perms       => '0644',
      source      => '/etc/cvmfs/default.local.ctmpl',
      destination => '/etc/cvmfs/default.local',
      command     => '/usr/bin/cvmfs_config reload',
    }
  }

  service { 'autofs':
    ensure    => running,
    enable    => true,
    subscribe => Exec['init_default.local'],
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
