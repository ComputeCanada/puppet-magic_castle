class profile::nfs {
  $server_ip = lookup('profile::nfs::client::server_ip')
  $ipaddress = lookup('terraform.self.local_ip')

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

  $instances = lookup('terraform.instances')
  $nfs_server = keys($instances.filter| $key, $values | { $values['local_ip'] == $server_ip })[0]
  $nfs_volumes = $instances[$nfs_server]['volumes']['nfs']
  if $nfs_volumes =~ Hash[String, Array[String]] {
    $nfs_export_list = keys($nfs_volumes)
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
  Hash[String, Array[String]] $devices,
  Array[String] $no_root_squash_tags = ['mgmt']
) {
  $nfs_domain  = "int.${domain_name}"

  class { 'nfs':
    server_enabled             => true,
    nfs_v4                     => true,
    storeconfigs_enabled       => false,
    nfs_v4_export_root         => '/export',
    nfs_v4_export_root_clients => "*.${nfs_domain}(ro,fsid=root,insecure,no_subtree_check,async,root_squash)",
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
    # Allow instances with specific tags to mount NFS without root squash
    $instances = lookup('terraform.instances')
    $common_options = 'rw,async,no_all_squash,security_label'
    $prefixes  = $instances.filter|$key, $values| { ! intersection($values['tags'], $no_root_squash_tags ).empty }.map|$key, $values| { $values['prefix'] }.unique
    $prefix_rules = $prefixes.map|$string| { "${string}*.${nfs_domain}(${common_options},no_root_squash)" }.join(' ')
    $clients = "${prefix_rules} *.${nfs_domain}(${common_options},root_squash)"
    $devices.each | String $key, $glob | {
      profile::nfs::server::export_volume { $key:
        clients         => $clients,
        glob            => $glob,
        root_bind_mount => true,
      }
    }
  }
}

define profile::nfs::server::export_volume (
  String $clients,
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

  nfs::server::export { "/mnt/${name}":
    ensure  => 'mounted',
    clients => $clients,
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
