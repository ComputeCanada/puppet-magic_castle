class profile::cvmfs::client (
  Integer $quota_limit,
  String $initial_profile,
  Array[String] $repositories,
  Array[String] $lmod_default_modules,
  Array[String] $alien_cache_repositories,

){
  include profile::cvmfs::local_user
  $alien_fs_root_raw = lookup('profile::cvmfs::alien_cache::alien_fs_root', undef, undef, 'scratch')
  $alien_fs_root = regsubst($alien_fs_root_raw, '^/|/$', '', 'G')
  $alien_folder_name_raw = lookup('profile::cvmfs::alien_cache::alien_folder_name', undef, undef, 'cvmfs_alien_cache')
  $alien_folder_name = regsubst($alien_folder_name_raw, '^/|/$', '', 'G')

  package { 'cvmfs-repo':
    ensure   => 'installed',
    provider => 'rpm',
    name     => 'cvmfs-release-3-2.noarch',
    source   => 'https://ecsft.cern.ch/dist/cvmfs/cvmfs-release/cvmfs-release-3-2.noarch.rpm',
  }

  if $facts['software_stack'] == 'eessi' {
    package { 'stack':
      ensure   => 'latest',
      provider => 'rpm',
      name     => 'cvmfs-config-eessi',
      source   => 'https://github.com/EESSI/filesystem-layer/releases/download/latest/cvmfs-config-eessi-latest.noarch.rpm',
    }
  } elsif $facts['software_stack'] == 'computecanada' {
    package { 'cc-cvmfs-repo':
      ensure   => 'installed',
      provider => 'rpm',
      name     => 'computecanada-release-1.0-1.noarch',
      source   => 'https://package.computecanada.ca/yum/cc-cvmfs-public/prod/RPM/computecanada-release-latest.noarch.rpm',
    }

    package { 'stack':
      ensure  => 'installed',
      name    => 'cvmfs-config-computecanada',
      require => [Package['cc-cvmfs-repo']],
    }
  }

  package { ['cvmfs', 'cvmfs-config-default', 'cvmfs-auto-setup']:
    ensure  => 'installed',
    require => [Package['cvmfs-repo'], Package['stack']],
  }

  file { '/etc/cvmfs/default.local.ctmpl':
    content => epp('profile/cvmfs/default.local', {
      'quota_limit'  => $quota_limit,
      'repositories' => $repositories + $alien_cache_repositories,
    }),
    notify  => Service['consul-template'],
    require => Package['cvmfs'],
  }

  $alien_cache_repositories.each |$repo| {
    file { "/etc/cvmfs/config.d/${repo}.conf":
      ensure  => 'present',
      content => epp('profile/cvmfs/alien_cache.conf.epp', {
        'alien_fs_root'     => $alien_fs_root,
        'alien_folder_name' => $alien_folder_name,
      }),
      require => Package['cvmfs']
    }
  }

  consul::service{ 'cvmfs':
    require => Tcp_conn_validator['consul'],
    token   => lookup('profile::consul::acl_api_token'),
    meta    => {
      arch => $facts['cpu_ext'],
    },
  }

  file { '/etc/consul-template/z-00-rsnt_arch.sh.ctmpl':
    source => 'puppet:///modules/profile/cvmfs/z-00-rsnt_arch.sh.ctmpl',
    notify => Service['consul-template'],
  }

  file { '/etc/profile.d/z-01-site.sh':
    content => epp('profile/cvmfs/z-01-site.sh',
      {
        'lmod_default_modules' => $lmod_default_modules,
        'initial_profile'      => $initial_profile,
      }
    ),
  }

  consul_template::watch { 'z-00-rsnt_arch.sh':
    require     => File['/etc/consul-template/z-00-rsnt_arch.sh.ctmpl'],
    config_hash => {
      perms       => '0644',
      source      => '/etc/consul-template/z-00-rsnt_arch.sh.ctmpl',
      destination => '/etc/profile.d/z-00-rsnt_arch.sh',
      command     => '/usr/bin/true',
    },
  }

  consul_template::watch { '/etc/cvmfs/default.local':
    require     => File['/etc/cvmfs/default.local.ctmpl'],
    config_hash => {
      perms       => '0644',
      source      => '/etc/cvmfs/default.local.ctmpl',
      destination => '/etc/cvmfs/default.local',
      command     => '/usr/bin/cvmfs_config reload',
    },
  }

  service { 'autofs':
    ensure => running,
    enable => true,
  }

  # Make sure CVMFS repos are mounted when requiring this class
  exec { 'init_default.local':
    command     => 'consul-template -template="/etc/cvmfs/default.local.ctmpl:/etc/cvmfs/default.local" -once',
    environment => ["CONSUL_TOKEN=${lookup('profile::consul::acl_api_token')}"],
    path        => ['/bin', '/usr/bin', $consul_template::bin_dir],
    unless      => 'test -f /etc/cvmfs/default.local',
    require     => [
      File['/etc/cvmfs/default.local.ctmpl'],
      Service['consul'],
      Service['autofs'],
    ],
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

# Create an alien source that refers to the uid and gid of cvmfs user
class profile::cvmfs::alien_cache (
  String $alien_fs_root_raw = 'scratch',
  String $alien_folder_name_raw = 'cvmfs_alien_cache',
) {
  $uid = lookup('profile::cvmfs::local_user::uid', undef, undef, 13000004)
  $gid = lookup('profile::cvmfs::local_user::gid', undef, undef, 8000131)
  $alien_fs_root = regsubst($alien_fs_root_raw, '^/|/$', '', 'G')
  $alien_folder_name = regsubst($alien_folder_name_raw, '^/|/$', '', 'G')

  file {"/mnt/${alien_fs_root}/${alien_folder_name}":
    ensure => directory,
    group  => $gid,
    owner  => $uid,
    require => File["/mnt/${alien_fs_root}/"]
  }
}

# Create a local cvmfs user
class profile::cvmfs::local_user (
  String $uname = 'cvmfs',
  String $group = 'cvmfs-reserved',
  Integer $uid = 13000004,
  Integer $gid = 8000131,
  String $selinux_user = 'unconfined_u',
  String $mls_range = 's0-s0:c0.c1023',
) {
  group { $group:
    ensure => present,
    gid    => $gid,
    before => Package['cvmfs'],
  }
  user { $uname:
    ensure     => present,
    forcelocal => true,
    uid        => $uid,
    gid        => $gid,
    managehome => false,
    home       => '/var/lib/cvmfs',
    shell      => '/usr/sbin/nologin',
    require    => Group[$group],
    before     => Package['cvmfs'],
  }
  if $group != 'cvmfs' {
    # cvmfs rpm create a user and a group 'cvmfs' if they do not exist.
    # If the group created for the local user 'cvmfs' is not named 'cvmfs',
    # we make sure the group created by the rpm is removed after the rpm install.
    group { 'cvmfs':
      ensure  => absent,
      require => Package['cvmfs'],
    }
  }
}
