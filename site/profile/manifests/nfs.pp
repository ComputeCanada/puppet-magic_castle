class profile::nfs {
  $server_ip = lookup('profile::nfs::client::server_ip')
  $interface = profile::getlocalinterface()
  $ipaddress = $facts['networking']['interfaces'][$interface]['ip']

  if $ipaddress == $server_ip {
    include profile::nfs::server
  } else {
    include profile::nfs::client
  }
}

class profile::nfs::client (
  String $server_ip,
  String $domain_name,
) {
  $nfs_domain  = "int.${domain_name}"

  class { 'nfs':
    client_enabled      => true,
    nfs_v4_client       => true,
    nfs_v4_idmap_domain => $nfs_domain,
  }

  $nfs_server = keys(lookup('terraform.instances').filter| $key, $values | { $values['local_ip'] == $server_ip })[0]
  $devices = lookup("terraform.instances.${nfs_server}.volumes.nfs", Hash[String, Array[String]], 'first', {})
  if $devices =~ Hash[String, Array[String]] {
    $nfs_export_list = keys($devices)
    $options_nfsv4 = 'proto=tcp,nosuid,nolock,noatime,actimeo=3,nfsvers=4.2,seclabel,x-systemd.automount,x-systemd.mount-timeout=30,_netdev'
    $nfs_export_list.each | String $name | {
      nfs::client::mount { "/${name}":
        ensure        => present,
        server        => $server_ip,
        share         => $name,
        options_nfsv4 => $options_nfsv4,
        notify        => Systemd::Daemon_reload['nfs-automount'],
      }
    }
  }

  ensure_resource('systemd::daemon_reload', 'nfs-automount')
  exec { 'systemctl restart remote-fs.target':
    subscribe   => Systemd::Daemon_reload['nfs-automount'],
    refreshonly => true,
    path        => ['/bin', '/usr/bin'],
  }
}

class profile::nfs::server (
  String $domain_name,
  Hash[String, Array[String]] $devices = lookup(
    "terraform.instances.${facts['networking']['hostname']}.volumes.nfs",
    Hash[String, Array[String]],
    'first', {}
  ),
) {
  $nfs_domain  = "int.${domain_name}"

  $cidr = profile::getcidr()
  class { 'nfs':
    server_enabled             => true,
    nfs_v4                     => true,
    storeconfigs_enabled       => false,
    nfs_v4_export_root         => '/export',
    nfs_v4_export_root_clients => "${cidr}(ro,fsid=root,insecure,no_subtree_check,async,root_squash)",
    nfs_v4_idmap_domain        => $nfs_domain,
  }

  file { '/etc/nfs.conf':
    owner  => 'root',
    group  => 'root',
    mode   => '0644',
    source => 'puppet:///modules/profile/nfs/nfs.conf',
    notify => Service[$nfs::server_service_name],
  }

  service { ['rpc-statd', 'rpcbind', 'rpcbind.socket']:
    ensure => stopped,
    enable => mask,
    notify => Service[$nfs::server_service_name],
  }

  package { 'lvm2':
    ensure => installed,
  }

  if $devices =~ Hash[String, Array[String]] {
    $hostname = $facts['networking']['hostname']
    $instance_tags = lookup("terraform.instances.${hostname}.tags")
    $ldap_access_tags = lookup('profile::users::ldap::access_tags').map|$tag| { split($tag, /:/)[0] }
    $users_tags = unique(
      flatten(
        lookup('profile::users::ldap::users').map|$key,$values| {
          if has_key($values, 'access_tags') {
            $values['access_tags'].map|$tag| { split($tag, /:/)[0] }
          } else {
            $ldap_access_tags
          }
        }
      )
    )
    $devices.each | String $key, $glob | {
      profile::nfs::server::export_volume { $key:
        glob            => $glob,
        root_bind_mount => ! intersection($instance_tags, $users_tags).empty,
      }
    }
  }
}

define profile::nfs::server::export_volume (
  Array[String] $glob,
  Boolean $root_bind_mount = false,
  String $seltype = 'home_root_t',
) {
  $regexes = regsubst($glob, /[?*]/, { '?' => '.', '*' => '.*' })

  ensure_resource('file', "/mnt/${name}", { 'ensure' => 'directory', 'seltype' => $seltype })

  $pool = $::facts['/dev/disk'].filter |$key, $values| {
    $regexes.any|$regex| {
      $key =~ Regexp($regex)
    }
  }.map |$key, $values| {
    $values
  }.unique

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
    notify  => Selinux::Exec_restorecon["/mnt/${name}"],
  }

  selinux::exec_restorecon { "/mnt/${name}": }

  $cidr = profile::getcidr()
  nfs::server::export { "/mnt/${name}":
    ensure  => 'mounted',
    clients => "${cidr}(rw,async,root_squash,no_all_squash,security_label)",
    notify  => Service[$nfs::server_service_name],
    require => [
      Mount["/mnt/${name}"],
      Class['nfs'],
    ],
  }
  if $root_bind_mount {
    ensure_resource('file', "/${name}", { 'ensure' => 'directory', 'seltype' => $seltype })
    mount { "/${name}":
      ensure  => mounted,
      device  => "/mnt/${name}",
      fstype  => none,
      options => 'rw,bind',
      require => File["/${name}"],
    }
  }
}
