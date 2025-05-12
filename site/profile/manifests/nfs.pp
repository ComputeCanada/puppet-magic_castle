class profile::nfs (String $domain) {
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
) {
  $nfs_domain = lookup('profile::nfs::domain')
  class { 'nfs':
    client_enabled      => true,
    nfs_v4_client       => true,
    nfs_v4_idmap_domain => $nfs_domain,
  }

  $instances = lookup('terraform.instances')
  $nfs_server = Hash($instances.map| $key, $values | { [$values['local_ip'], $key] })[$server_ip]
  $nfs_volumes = $instances.dig($nfs_server, 'volumes', 'nfs')
  $self_volumes = lookup('terraform.self.volumes')
  if $nfs_volumes =~ Hash[String, Hash] {
    $nfs_export_list = keys($nfs_volumes)
    $options_nfsv4 = 'proto=tcp,nosuid,nolock,noatime,actimeo=3,nfsvers=4.2,seclabel,x-systemd.automount,x-systemd.mount-timeout=30,_netdev'
    $nfs_export_list.each | String $name | {
      if $self_volumes.any |$tag, $volume_hash| { $name in $volume_hash } {
        $mount_name = "nfs-${name}"
      } else {
        $mount_name = $name
      }
      nfs::client::mount { "/${mount_name}":
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
  Array[String] $no_root_squash_tags = ['mgmt']
) {
  include profile::volumes

  $nfs_domain = lookup('profile::nfs::domain')
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

  $devices = lookup('terraform.self.volumes.nfs', Hash, undef, {})
  if $devices =~ Hash[String, Hash] {
    # Allow instances with specific tags to mount NFS without root squash
    $instances = lookup('terraform.instances')
    $common_options = 'rw,async,no_all_squash,security_label'
    $prefixes  = $instances.filter|$key, $values| { ! intersection($values['tags'], $no_root_squash_tags ).empty }.map|$key, $values| { $values['prefix'] }.unique
    $prefix_rules = $prefixes.map|$string| { "${string}*.${nfs_domain}(${common_options},no_root_squash)" }.join(' ')
    $clients = "${prefix_rules} *.${nfs_domain}(${common_options},root_squash)"
    $devices.each | String $key, $glob | {
      nfs::server::export { "/mnt/nfs/${key}":
        ensure  => 'mounted',
        clients => $clients,
        notify  => Service[$nfs::server_service_name],
        require => [
          Profile::Volumes::Volume["nfs-${key}"],
          Class['nfs'],
        ],
      }
    }
  }
}
