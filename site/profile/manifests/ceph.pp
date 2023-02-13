class profile::ceph::client (
  String $share_name,
  String $access_key,
  String $export_path,
  Array[String] $mon_host,
  Array[String] $mount_binds = [],
  String $mount_name = 'cephfs01',
  String $binds_fcontext_equivalence = '/home',
) {
  class { 'profile::ceph::client::config':
    share_name  => $share_name,
    access_key  => $access_key,
    export_path => $export_path,
    mon_host    => $mon_host,
  }

  file { "/mnt/${mount_name}":
    ensure => directory,
  }

  $mon_host_string = join($mon_host, ',')
  mount { "/mnt/${mount_name}":
    ensure  => 'mounted',
    fstype  => 'ceph',
    device  => "${mon_host_string}:${export_path}",
    options => "name=${share_name},secretfile=/etc/ceph/client.keyonly.${share_name}",
    require => Class['profile::ceph::client::config'],
  }

  $mount_binds.each |$mount| {
    file { "/mnt/${mount_name}/${mount}":
      ensure  => directory,
      require => Class['profile::ceph::client::config'],
    }
    file { "/${mount}":
      ensure  => directory,
      require => Class['profile::ceph::client::config'],
    }
    mount { "/${mount}":
      ensure  => 'mounted',
      fstype  => 'none',
      options => 'rw,bind',
      device  => "/mnt/${mount_name}/${mount}",
      require => [
        File["/mnt/${mount_name}/${mount}"],
        File["/${mount}"],
      ],
    }

    if ($binds_fcontext_equivalence != '' and "/${mount}" != $binds_fcontext_equivalence) {
      selinux::fcontext::equivalence { "/${mount}":
        ensure  => 'present',
        target  => $binds_fcontext_equivalence,
        require => Mount["/${mount}"],
        notify  => Selinux::Exec_restorecon["/${mount}"],
      }
      selinux::exec_restorecon { "/${mount}": }
    }
  }
}

class profile::ceph::client::install {
  yumrepo { 'ceph-stable':
    ensure        => present,
    enabled       => true,
    baseurl       => "https://download.ceph.com/rpm-nautilus/el${$::facts['os']['release']['major']}/${::facts['architecture']}/",
    gpgcheck      => 1,
    gpgkey        => 'https://download.ceph.com/keys/release.asc',
    repo_gpgcheck => 0,
  }

  if ($::facts['os']['release']['major'] == '8') {
    $argparse_pkgname = 'python3-ceph-argparse'
  } else {
    $argparse_pkgname = 'python-ceph-argparse'
  }

  package {
    [
      'libcephfs2',
      'python-cephfs',
      'ceph-common',
      $argparse_pkgname,
      # 'ceph-fuse',
    ]:
      ensure  => installed,
      require => [Yumrepo['epel'], Yumrepo['ceph-stable']],
  }
}

class profile::ceph::client::config (
  String $share_name,
  String $access_key,
  String $export_path,
  Array[String] $mon_host,
) {
  require profile::ceph::client::install

  $client_fullkey = @("EOT")
    [client.${share_name}]
    key = ${access_key}
    | EOT

  file { "/etc/ceph/client.fullkey.${share_name}":
    content => $client_fullkey,
    mode    => '0600',
    owner   => 'root',
    group   => 'root',
  }

  file { "/etc/ceph/client.keyonly.${share_name}":
    content => Sensitive($access_key),
    mode    => '0600',
    owner   => 'root',
    group   => 'root',
  }

  $mon_host_string = join($mon_host, ',')
  $ceph_conf = @("EOT")
    [client]
    client quota = true
    mon host = ${mon_host_string}
    | EOT

  file { '/etc/ceph/ceph.conf':
    content => $ceph_conf,
  }
}
