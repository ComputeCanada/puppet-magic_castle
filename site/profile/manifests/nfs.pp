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
      options_nfsv4 => 'proto=tcp,nolock,noatime,actimeo=3,nfsvers=4.2,seclabel'
  }
  nfs::client::mount { '/scratch':
      server        => $server_ip,
      share         => 'scratch',
      options_nfsv4 => 'proto=tcp,nolock,noatime,actimeo=3,nfsvers=4.2,seclabel'
  }
}

class profile::nfs::server {
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

  file { ['/project', '/scratch', '/mnt/home'] :
    ensure  => directory,
  }

  package { 'lvm2':
    ensure => installed
  }

  # Activate volume group following a rebuild of the server
  exec { 'vgchange-data_volume_group':
    command => 'vgchange -ay data_volume_group',
    onlyif  => ['test ! -d /dev/data_volume_group', 'vgscan -t | grep -q "data_volume_group"'],
    require => [Package['lvm2']],
    path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
  }

  $home_size = lookup('profile::nfs::server::home_size')
  $project_size = lookup('profile::nfs::server::project_size')
  $scratch_size = lookup('profile::nfs::server::scratch_size')

  $devices = keys($::disks).map |$disk| { "/dev/${disk}" }
  $parts2disks = unique(keys($::partitions).map |$part| {
    $part ? {
      /^.*p\d+$/ => regsubst($part, '^(.*)(p\\d+)','\\1'),
      /^.*\d+$/  => regsubst($part, '^(.*)(\\d+)', '\\1'),
      default    => $part
    }
  })
  $exclusion = $parts2disks + ['/dev/sr0', '/dev/fd0', '/dev/scd0']
  $pooldisks = $devices.filter |$x| { !( $x in $exclusion ) }

  class { 'lvm':
    require       => Exec['vgchange-data_volume_group'],
    volume_groups => {
      'data_volume_group' => {
        physical_volumes => $pooldisks,
        createonly       => true,
        logical_volumes  => {
          'datapool' => {
            'thinpool' => true,
            'createfs' => false,
            'mounted'  => false,
          },
          'home'     => {
            'size'              => $home_size,
            'fs_type'           => 'xfs',
            'mountpath'         => '/mnt/home',
            'mountpath_require' => true,
            'thinpool'          => 'datapool',
          },
          'project'  => {
            'size'              => $project_size,
            'fs_type'           => 'xfs',
            'mountpath_require' => true,
            'thinpool'          => 'datapool',
          },
          'scratch'  => {
            'size'              => $scratch_size,
            'fs_type'           => 'xfs',
            'mountpath_require' => true,
            'thinpool'          => 'datapool',
          },
        },
      },
    },
  }

  exec { 'semanage_fcontext_mnt_home':
    command => 'semanage fcontext -a -e /home /mnt/home',
    unless  => 'grep -q "/mnt/home\s*/home" /etc/selinux/targeted/contexts/files/file_contexts.subs*',
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    require => Mount['/mnt/home'],
  }

  exec { 'semanage_fcontext_project':
    command => 'semanage fcontext -a -e /home /project',
    unless  => 'grep -q "/project\s*/home" /etc/selinux/targeted/contexts/files/file_contexts.subs*',
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    require => Mount['/project'],
  }

  exec { 'semanage_fcontext_scratch':
    command => 'semanage fcontext -a -e /home /scratch',
    unless  => 'grep -q "/scratch\s*/home" /etc/selinux/targeted/contexts/files/file_contexts.subs*',
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    require => Mount['/scratch'],
  }

  nfs::server::export{ '/mnt/home' :
    ensure  => 'mounted',
    clients => "${cidr}(rw,async,no_root_squash,no_all_squash,security_label)",
    notify  => Service['nfs-idmap.service'],
    require => Mount['/mnt/home'],
  }

  nfs::server::export{ '/project':
    ensure  => 'mounted',
    clients => "${cidr}(rw,async,no_root_squash,no_all_squash,security_label)",
    notify  => Service['nfs-idmap.service'],
    require => Mount['/project'],
  }

  nfs::server::export{ '/scratch':
    ensure  => 'mounted',
    clients => "${cidr}(rw,async,no_root_squash,no_all_squash,security_label)",
    notify  => Service['nfs-idmap.service'],
    require => Mount['/scratch'],
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
