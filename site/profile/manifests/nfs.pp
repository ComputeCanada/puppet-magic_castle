class profile::nfs::client (String $server_ip) {
  $domain_name = lookup({ name          => 'profile::freeipa::base::domain_name',
                          default_value => $::domain })
  $nfs_domain  = "int.${domain_name}"

  class { '::nfs':
    client_enabled      => true,
    nfs_v4_client       => true,
    nfs_v4_idmap_domain => $nfs_domain
  }

  $nfs_export_list = keys(lookup('profile::nfs::server::devices', undef, undef, {}))
  $options_nfsv4 = 'proto=tcp,nosuid,nolock,noatime,actimeo=3,nfsvers=4.2,seclabel,bg'
  $nfs_export_list.each | String $name | {
    nfs::client::mount { "/${name}":
        server        => $server_ip,
        share         => $name,
        options_nfsv4 => $options_nfsv4
    }
  }
}

class profile::nfs::server (
  Hash[String, Array[String]] $devices,
) {
  require profile::base

  $domain_name = lookup({ name          => 'profile::freeipa::base::domain_name',
                          default_value => $::domain })
  $nfs_domain  = "int.${domain_name}"

  file { '/lib/systemd/system/clean-nfs-rbind.service':
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
    content => @(END)
[Unit]
Before=nfs-server.service

[Service]
Type=oneshot
RemainAfterExit=true
ExecStop=/usr/bin/sed "-i ';/export/;d' /etc/fstab"

[Install]
WantedBy=multi-user.target
END
  }

  exec { 'clean-nfs-rbind-systemd-reload':
    command     => 'systemctl daemon-reload',
    path        => [ '/usr/bin', '/bin', '/usr/sbin' ],
    refreshonly => true,
    require     => File['/lib/systemd/system/clean-nfs-rbind.service']
  }

  service { 'clean-nfs-rbind':
    ensure  => running,
    enable  => true,
    require => Exec['clean-nfs-rbind-systemd-reload']
  }

  $cidr = profile::getcidr()
  class { '::nfs':
    server_enabled             => true,
    nfs_v4                     => true,
    storeconfigs_enabled       => false,
    nfs_v4_export_root         => '/export',
    nfs_v4_export_root_clients => "${cidr}(ro,fsid=root,insecure,no_subtree_check,async,root_squash)",
    nfs_v4_idmap_domain        => $nfs_domain
  }

  file { '/etc/nfs.conf':
    ensure => present,
    owner  => 'root',
    group  => 'root',
    mode   => '0644',
    source => 'puppet:///modules/profile/nfs/nfs.conf',
    notify => Service[$::nfs::server_service_name],
  }

  service { ['rpc-statd', 'rpcbind', 'rpcbind.socket']:
    ensure => stopped,
    enable => mask,
    notify => Service[$::nfs::server_service_name],
  }

  package { 'lvm2':
    ensure => installed
  }

  $devices.each | String $key, $glob | {
    profile::nfs::server::export_volume { $key:
      glob => $glob,
    }
  }

  exec { 'unexportfs_exportfs':
    command => 'exportfs -ua; cat /proc/fs/nfs/exports; exportfs -a',
    path    => ['/usr/sbin', '/usr/bin'],
    unless  => 'grep -qvP "(^#|^/export\s)" /proc/fs/nfs/exports'
  }
}

define profile::nfs::server::export_volume (
  Array[String] $glob,
  String $seltype = 'home_root_t',
) {

  $regexes =  regsubst($glob, /[?*]/, {'?' => '.', '*' => '.*' })

  file { ["/mnt/${name}"] :
    ensure  => directory,
    seltype => $seltype,
  }

  $pool = $::facts['/dev/disk'].filter |$key, $values| {
    $regexes.any|$regex| {
      $key =~ Regexp($regex)
    }
  }.map |$key, $values| {
    $values
  }

  exec { "vgchange-${name}_vg":
    command => "vgchange -ay ${name}_vg",
    onlyif  => ["test ! -d /dev/${name}_vg", "vgscan -t | grep -q '${name}_vg'"],
    require => [Package['lvm2']],
    path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
  }

  physical_volume { $pool:
    ensure => present,
  }

  volume_group { "${name}_vg":
    ensure           => present,
    physical_volumes => $pool,
    createonly       => true,
    followsymlinks   => true,
  }

  lvm::logical_volume { $name:
    ensure            => present,
    volume_group      => "${name}_vg",
    fs_type           => 'xfs',
    mountpath         => "/mnt/${name}",
    mountpath_require => true,
  }

  selinux::fcontext::equivalence { "/mnt/${name}":
    ensure  => 'present',
    target  => '/home',
    require => Mount["/mnt/${name}"],
    notify  => Selinux::Exec_restorecon["/mnt/${name}"]
  }

  selinux::exec_restorecon { "/mnt/${name}": }

  nfs::server::export{ "/mnt/${name}":
    ensure  => 'mounted',
    clients => "${cidr}(rw,async,root_squash,no_all_squash,security_label)",
    notify  => Service[$::nfs::server_service_name],
    require => [
      Mount["/mnt/${name}"],
      Class['::nfs'],
    ]
  }
}
