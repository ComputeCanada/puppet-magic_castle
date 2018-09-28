class common {
  include stdlib

  class { selinux:
    mode => 'enforcing',
    type => 'targeted',
  }
  package { 'selinux-policy':
    ensure => 'latest'
  }

  service { 'rsyslog':
    ensure => running,
    enable => true
  }

  service { 'dbus':
    ensure => running,
    enable => true
  }

  class { '::swap_file':
    files => {
      '/mnt/swap' => {
        ensure   => present,
        swapfile => '/mnt/swap',
        swapfilesize => '1 GB',
      },
    },
  }

  package { 'systemd':
    ensure => 'latest'
  }

  package { 'vim':
    ensure => 'installed'
  }
  package { 'rsyslog':
    ensure => 'installed'
  }

  service { 'firewalld':
    ensure => 'stopped',
    enable => 'mask'
  }

  package { ['iptables', 'iptables-services'] :
    ensure => 'installed'
  }

  yumrepo { 'epel':
    baseurl        => 'http://dl.fedoraproject.org/pub/epel/$releasever/$basearch',
    enabled        => "true",
    failovermethod => "priority",
    gpgcheck       => "false",
    gpgkey         => "file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL",
    descr          => "Extra Packages for Enterprise Linux"
  }

  yumrepo { 'elrepo':
    descr    => "ELRepo.org Community Enterprise Linux Repository - el7",
    baseurl  => 'http://muug.ca/mirror/elrepo/elrepo/el7/$basearch/',
    enabled  => "true",
    gpgcheck => "false",
    gpgkey   => "file:///etc/pki/rpm-gpg/RPM-GPG-KEY-elrepo.org",
    protect  => "false"
  }

  include slurm::base
}

class client {
  # rsyslog
  file_line { 'remote_host':
    ensure => present,
    path   => "/etc/rsyslog.conf",
    match  => '^#\*.\* @@remote-host:514',
    line   => '*.* @@mgmt01:514',
    notify => Service['rsyslog']
  }

  # FreeIPA
  include freeipa::client

  # NFS
  class { '::nfs':
    client_enabled => true,
    nfs_v4_client  => true,
  }
  selinux::boolean { 'use_nfs_home_dirs': }
  nfs::client::mount { '/home':
      server => 'mgmt01',
      share => 'home'
  }
  nfs::client::mount { '/project':
      server => 'mgmt01',
      share => 'project'
  }
  nfs::client::mount { '/scratch':
      server => 'mgmt01',
      share => 'scratch'
  }
  nfs::client::mount { '/etc/slurm':
      server => 'mgmt01',
      share => 'slurm'
  }

  # CVMFS
  package { 'cvmfs-repo':
    name     => 'cvmfs-release-2-6.noarch',
    provider => 'rpm',
    ensure   => 'installed',
    source   => 'https://ecsft.cern.ch/dist/cvmfs/cvmfs-release/cvmfs-release-latest.noarch.rpm'
  }
  package { 'cc-cvmfs-repo':
    name     => 'computecanada-release-1.0-1.noarch',
    provider => 'rpm',
    ensure   => 'installed',
    source   => 'https://package.computecanada.ca/yum/cc-cvmfs-public/Packages/computecanada-release-1.0-1.noarch.rpm'
  }
  package { ['cvmfs', 'cvmfs-config-computecanada', 'cvmfs-config-default', 'cvmfs-auto-setup']:
    ensure => 'installed',
    require => [Package['cvmfs-repo'], Package['cc-cvmfs-repo']]
  }
  file { '/etc/cvmfs/default.local':
    ensure  => 'present',
    content => file('cvmfs/default.local'),
    require => Package['cvmfs']
  }
  file { '/etc/profile.d/z-00-computecanada.sh':
    ensure  => 'present',
    content => file('cvmfs/z-00-computecanada.sh'),
    require => File['/etc/cvmfs/default.local']
  }
  service { 'autofs':
    ensure  => running,
    enable  => true,
    require => File['/etc/cvmfs/default.local']
  }
}

node default {
  include common
}

node /^mgmt\d+$/ {
  include common
  $masklen = netmask_to_masklen("$netmask")
  $cidr    = "$network/$masklen"

  # FreeIPA
  include freeipa::server
  include freeipa::guest_accounts

  # rsyslog
  file_line { 'rsyslog_modload_imtcp':
    ensure => present,
    path   => "/etc/rsyslog.conf",
    match  => '^#$ModLoad imtcp',
    line   => '$ModLoad imtcp',
    notify => Service['rsyslog']
  }
  file_line { 'rsyslog_InputTCPServerRun':
    ensure => present,
    path   => "/etc/rsyslog.conf",
    match  => '^#$InputTCPServerRun 514',
    line   => '$InputTCPServerRun 514',
    notify => Service['rsyslog']
  }

  # Squid
  package { "squid":
    ensure => "installed"
  }

  service { 'squid':
    ensure => 'running',
    enable => 'true'
  }

  file { '/etc/squid/squid.conf':
    ensure  => 'present',
    content => epp('squid/squid.conf', {'cidr' => $cidr})
  }

  # Shared folders
  file { ['/project', '/scratch'] :
    ensure  => directory,
    seltype => 'usr_t'
  }

  file { ['/project/6002799', '/project/6002799/photos'] :
    ensure => directory
  }

  file { '/project/6002799/photos/KSC2018.jpg':
    ensure => 'present',
    source => "https://images-assets.nasa.gov/image/KSC-20180316-PH_JBS01_0118/KSC-20180316-PH_JBS01_0118~orig.JPG"
  }

  file { "/project/6002799/photos/VAFB2018.jpg":
    ensure => 'present',
    source => "https://images-assets.nasa.gov/image/VAFB-20180302-PH_ANV01_0056/VAFB-20180302-PH_ANV01_0056~orig.jpg"
  }

  # NFS
  class { '::nfs':
    server_enabled => true,
    nfs_v4 => true,
    storeconfigs_enabled => false,
    nfs_v4_export_root  => "/export",
    nfs_v4_export_root_clients => "$cidr(ro,fsid=root,insecure,no_subtree_check,async,root_squash)"
  }
  nfs::server::export{ ['/etc/slurm', '/home', '/project', '/scratch'] :
    ensure  => 'mounted',
    clients => "$cidr(rw,sync,no_root_squash,no_all_squash)"
  }

  # Slurm Controller
  include slurm::controller
}

node /^login\d+$/ {
  include common
  include client
  include jupyterhub
}

node /^node\d+$/ {
  include common
  class { 'client':
    before => Class['slurm::node']
  }
  include slurm::node

  file_line { 'kmod_nvidia_exclude':
    ensure => present,
    path   => '/etc/yum.conf',
    line   => 'exclude=kmod-nvidia* nvidia-x11-drv',
  }

  package { 'kmod-nvidia-390.48':
    ensure  => 'installed',
    require => File_line['kmod_nvidia_exclude']
  }

}
