class profile::nfs::client (String $server_ip) {
  $domain_name = lookup({ name          => 'profile::freeipa::base::domain_name',
                          default_value => $::domain })
  $nfs_domain  = "int.${domain_name}"

  class { '::nfs':
    client_enabled      => true,
    nfs_v4_client       => true,
    nfs_v4_idmap_domain => $nfs_domain
  }

  # use_nfs_home_dirs is not needed as long as we can export
  # the selinux file labels with 'security_label' in nfs server
  # and seclabel in nfs client.
  # selinux::boolean { 'use_nfs_home_dirs': }

  nfs::client::mount { '/home':
      server        => $server_ip,
      share         => 'home',
      options_nfsv4 => 'proto=tcp,nolock,noatime,actimeo=3,nfsvers=4.2,seclabel'
  }
  nfs::client::mount { '/project':
      server        => $server_ip,
      share         => 'project',
      options_nfsv4 => 'proto=tcp,nolock,noatime,actimeo=3,nfsvers=4.2'
  }
  nfs::client::mount { '/scratch':
      server        => $server_ip,
      share         => 'scratch',
      options_nfsv4 => 'proto=tcp,nolock,noatime,actimeo=3,nfsvers=4.2'
  }
}

class profile::nfs::server {
  $domain_name = lookup({ name          => 'profile::freeipa::base::domain_name',
                          default_value => $::domain })
  $nfs_domain  = "int.${domain_name}"

  file { ['/project', '/scratch'] :
    ensure  => directory,
    # seltype => 'usr_t'
  }

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
ExecStop=/usr/bin/sed -i '/\/export\//d' /etc/fstab

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

  file_line { 'rpc_nfs_args_v4.2':
    ensure => present,
    path   => '/etc/sysconfig/nfs',
    line   => 'RPCNFSDARGS="-V 4.2"',
    match  => '^RPCNFSDARGS\=',
    notify => Service['nfs-server.service']
  }

  nfs::server::export{ ['/mnt/home'] :
    ensure  => 'mounted',
    clients => "${cidr}(rw,async,no_root_squash,no_all_squash,security_label)",
    notify  => Service['nfs-idmap.service']
  }

  nfs::server::export{ ['/project', '/scratch']:
    ensure  => 'mounted',
    clients => "${cidr}(rw,async,no_root_squash,no_all_squash)",
    notify  => Service['nfs-idmap.service']
  }

  exec { 'unexportfs_exportfs':
    command => 'exportfs -ua; cat /proc/fs/nfs/exports; exportfs -a',
    path    => ['/usr/sbin', '/usr/bin'],
    onlyif  => 'grep -q "/export\s" /proc/fs/nfs/exports',
    require => [Nfs::Server::Export['/mnt/home'],
                Nfs::Server::Export['/project'],
                Nfs::Server::Export['/scratch']]
  }
}
