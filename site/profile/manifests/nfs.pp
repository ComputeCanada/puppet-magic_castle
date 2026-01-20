class profile::nfs (String $domain) {
  $server_ip = lookup('profile::nfs::client::server_ip', undef, undef, '')
  $ipaddress = lookup('terraform.self.local_ip')

  if $ipaddress == $server_ip {
    include profile::nfs::server
  } elsif $server_ip != '' {
    include profile::nfs::client
  }
}

class profile::nfs::client (
  String $server_ip,
  Optional[Array[String]] $share_names = [],
) {
  $nfs_domain = lookup('profile::nfs::domain')
  class { 'nfs':
    client_enabled      => true,
    nfs_v4_client       => true,
    nfs_v4_idmap_domain => $nfs_domain,
  }

  $instances = lookup('terraform.instances')
  $nfs_server = $instances.filter| $key, $values | { $values['local_ip'] == $server_ip }.map | $key, $values | { $values }
  $nfs_volumes = $nfs_server.get('0.volumes.nfs', {})
  $shares_to_mount = keys($nfs_volumes) + $share_names

  $self_volumes = lookup('terraform.self.volumes')
  if $facts['virtual'] =~ /^(container|lxc).*$/ {
    # automount relies on a kernel module that currently does not support namespace.
    # Therefore it is not compatible with containers.
    # https://superuser.com/a/1372700
    $mount_options = 'x-systemd.mount-timeout=infinity,retry=10000,fg'
  } else {
    $mount_options = 'x-systemd.automount,x-systemd.mount-timeout=30'
  }

  ensure_resource('systemd::daemon_reload', 'nfs-client')
  exec { 'systemctl restart remote-fs.target':
    subscribe   => Systemd::Daemon_reload['nfs-client'],
    refreshonly => true,
    tries       => 20, # trye to connect the nfs mounts for 5 minutes
    try_sleep   => 15,
    path        => ['/bin', '/usr/bin'],
  }

  $options_nfsv4 = "proto=tcp,nosuid,nolock,noatime,actimeo=3,nfsvers=4.2,seclabel,_netdev,${mount_options}"
  $shares_to_mount.each | String $share_name | {
    # If the instance has a volume mounted under the same name as the nfs share,
    # we mount the nfs share under /nfs/${share_name}.
    if $self_volumes.any |$tag, $volume_hash| { $share_name in $volume_hash } {
      $mount_point = "/nfs/${share_name}"
    } else {
      $mount_point = "/${share_name}"
    }
    nfs::client::mount { $mount_point:
      ensure        => present,
      server        => $server_ip,
      share         => $share_name,
      options_nfsv4 => $options_nfsv4,
      notify        => Systemd::Daemon_reload['nfs-client'],
    }
  }
}

class profile::nfs::server (
  Array[String] $no_root_squash_tags = ['mgmt'],
  Boolean $enable_client_quotas = false,
  Optional[Array[String]] $export_paths = [],
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

  if $enable_client_quotas {
    package { 'quota-rpc':
      ensure => 'installed',
    }
    service { 'rpc-rquotad':
      ensure  => 'running',
      enable  => true,
      require => [Service['rpcbind'], Service['rpcbind.socket'], Package['quota-rpc']]
    }
    service { ['rpcbind', 'rpcbind.socket']:
      enable => true,
      notify => Service[$nfs::server_service_name],
    }
  }
  else {
    service { ['rpcbind', 'rpcbind.socket']:
      ensure => stopped,
      enable => mask,
      notify => Service[$nfs::server_service_name],
    }
  }
  service { 'rpc-statd':
    ensure => stopped,
    enable => mask,
    notify => Service[$nfs::server_service_name],
  }

  $devices = lookup('terraform.self.volumes.nfs', Hash, undef, {})
  if $devices =~ Hash[String, Hash] {
    $export_path_list = $export_paths + $devices.map | String $key, $glob | { "/mnt/nfs/${key}" }
  } else {
    $export_path_list = $export_paths
  }
  $export_paths.each |$path| {
    ensure_resource('file', $path, { ensure => directory, before => Nfs::Server::Export[$path] })
  }

  if $export_path_list {
    # Allow instances with specific tags to mount NFS without root squash
    $instances = lookup('terraform.instances')
    $common_options = 'rw,async,no_all_squash,security_label'
    $prefixes  = $instances.filter|$key, $values| { ! intersection($values['tags'], $no_root_squash_tags ).empty }.map|$key, $values| { $values['prefix'] }.unique
    $prefix_rules = $prefixes.map|$string| { "${string}*.${nfs_domain}(${common_options},no_root_squash)" }.join(' ')
    $clients = "${prefix_rules} *.${nfs_domain}(${common_options},root_squash)"
    $export_path_list.each | String $path| {
      nfs::server::export { $path:
        ensure  => 'mounted',
        clients => $clients,
        notify  => Service[$nfs::server_service_name],
        require => Class['nfs'],
      }
    }
  }
  Profile::Volumes::Volume<| |> -> Nfs::Server::Export <| |>
  Mount <| |> -> Service <| tag == 'profile::accounts' and title == 'mkhome' |>
  Mount <| |> -> Service <| tag == 'profile::accounts' and title == 'mkproject' |>
}
