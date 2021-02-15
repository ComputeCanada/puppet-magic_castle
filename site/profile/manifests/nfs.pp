class profile::nfs::client (String $server_ip) {
  $domain_name = lookup({ name          => 'profile::freeipa::base::domain_name',
                          default_value => $::domain })
  $nfs_domain  = "int.${domain_name}"

  class { '::nfs':
    client_enabled      => true,
    nfs_v4_client       => true,
    nfs_v4_idmap_domain => $nfs_domain
  }

  $nfs_home    = ! empty(lookup('profile::nfs::server::home_devices', undef, undef, []))
  $nfs_project = ! empty(lookup('profile::nfs::server::project_devices', undef, undef, []))
  $nfs_scratch = ! empty(lookup('profile::nfs::server::scratch_devices', undef, undef, []))

  # Retrieve all folder exported with NFS in a single mount
  $options_nfsv4 = 'proto=tcp,nosuid,nolock,noatime,actimeo=3,nfsvers=4.2,seclabel,bg'
  if $nfs_home {
    nfs::client::mount { '/home':
        server        => $server_ip,
        share         => 'home',
        options_nfsv4 => $options_nfsv4
    }
  }
  if $nfs_project {
    nfs::client::mount { '/project':
        server        => $server_ip,
        share         => 'project',
        options_nfsv4 => $options_nfsv4
    }
  }
  if $nfs_scratch {
    nfs::client::mount { '/scratch':
        server        => $server_ip,
        share         => 'scratch',
        options_nfsv4 => $options_nfsv4
    }
  }
}

class profile::nfs::server {
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

  $home_devices    = lookup('profile::nfs::server::home_devices', undef, undef, [])
  $project_devices = lookup('profile::nfs::server::project_devices', undef, undef, [])
  $scratch_devices = lookup('profile::nfs::server::scratch_devices', undef, undef, [])

  if ! empty($home_devices) {
    file { ['/mnt/home'] :
      ensure  => directory,
      seltype => 'home_root_t',
    }
    $home_pool = glob($home_devices)
    exec { 'vgchange-home_vg':
      command => 'vgchange -ay home_vg',
      onlyif  => ['test ! -d /dev/home_vg', 'vgscan -t | grep -q "home_vg"'],
      require => [Package['lvm2']],
      path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    }

    physical_volume { $home_pool:
      ensure => present,
    }

    volume_group { 'home_vg':
      ensure           => present,
      physical_volumes => $home_pool,
      createonly       => true,
      followsymlinks   => true,
    }

    lvm::logical_volume { 'home':
      ensure            => present,
      volume_group      => 'home_vg',
      fs_type           => 'xfs',
      mountpath         => '/mnt/home',
      mountpath_require => true,
    }

    selinux::fcontext::equivalence { '/mnt/home':
      ensure  => 'present',
      target  => '/home',
      require => Mount['/mnt/home'],
    }

    nfs::server::export{ '/mnt/home' :
      ensure  => 'mounted',
      clients => "${cidr}(rw,async,root_squash,no_all_squash,security_label)",
      notify  => Service[$::nfs::server_service_name],
      require => [
        Mount['/mnt/home'],
        Class['::nfs'],
      ]
    }
  }

  if ! empty($project_devices) {
    file { ['/project'] :
      ensure  => directory,
      seltype => 'home_root_t',
    }
    $project_pool = glob($project_devices)
    exec { 'vgchange-project_vg':
      command => 'vgchange -ay project_vg',
      onlyif  => ['test ! -d /dev/project_vg', 'vgscan -t | grep -q "project_vg"'],
      require => [Package['lvm2']],
      path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    }

    physical_volume { $project_pool:
      ensure => present,
    }

    volume_group { 'project_vg':
      ensure           => present,
      physical_volumes => $project_pool,
      createonly       => true,
      followsymlinks   => true,
    }

    lvm::logical_volume { 'project':
      ensure            => present,
      volume_group      => 'project_vg',
      fs_type           => 'xfs',
      mountpath         => '/project',
      mountpath_require => true,
    }

    selinux::fcontext::equivalence { '/project':
      ensure  => 'present',
      target  => '/home',
      require => Mount['/project'],
    }

    nfs::server::export{ '/project':
      ensure  => 'mounted',
      clients => "${cidr}(rw,async,root_squash,no_all_squash,security_label)",
      notify  => Service[$::nfs::server_service_name],
      require => [
        Mount['/project'],
        Class['::nfs'],
      ]
    }
  }

  if ! empty($scratch_devices) {
    file { ['/scratch'] :
      ensure  => directory,
      seltype => 'home_root_t',
    }
    $scratch_pool = glob($scratch_devices)
    exec { 'vgchange-scratch_vg':
      command => 'vgchange -ay scratch_vg',
      onlyif  => ['test ! -d /dev/scratch_vg', 'vgscan -t | grep -q "scratch_vg"'],
      require => [Package['lvm2']],
      path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    }

    physical_volume { $scratch_pool:
      ensure => present,
    }

    volume_group { 'scratch_vg':
      ensure           => present,
      physical_volumes => $scratch_pool,
      createonly       => true,
      followsymlinks   => true,
    }

    lvm::logical_volume { 'scratch':
      ensure            => present,
      volume_group      => 'scratch_vg',
      fs_type           => 'xfs',
      mountpath         => '/scratch',
      mountpath_require => true,
    }

    selinux::fcontext::equivalence { '/scratch':
      ensure  => 'present',
      target  => '/home',
      require => Mount['/scratch'],
    }

    nfs::server::export{ '/scratch':
      ensure  => 'mounted',
      clients => "${cidr}(rw,async,root_squash,no_all_squash,security_label)",
      notify  => Service[$::nfs::server_service_name],
      require => [
        Mount['/scratch'],
        Class['::nfs'],
      ]
    }
  }

  exec { 'unexportfs_exportfs':
    command => 'exportfs -ua; cat /proc/fs/nfs/exports; exportfs -a',
    path    => ['/usr/sbin', '/usr/bin'],
    unless  => 'grep -qvP "(^#|^/export\s)" /proc/fs/nfs/exports'
  }
}
