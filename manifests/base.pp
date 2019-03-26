class profile::base {
  include stdlib

  class { selinux:
    mode => 'enforcing',
    type => 'targeted',
  }

  package { 'selinux-policy':
    ensure => 'latest'
  }

  package { 'yum-plugin-priorities':
    ensure => 'installed'
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

  package { 'vim':
    ensure => 'installed'
  }

  package { 'firewalld':
    ensure => 'absent',
  }

  class { 'firewall': }

  firewall { '001 drop access to metadata server':
    chain       => 'OUTPUT',
    proto       => 'tcp',
    destination => '169.254.169.254',
    action      => 'drop',
    uid         => '! root'
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

  package { 'haveged':
    ensure => 'installed',
    require => Yumrepo['epel']
  }

  service { 'haveged':
    ensure  => running,
    enable  => true,
    require => Package['haveged']
  }

  package { 'xauth':
    ensure => 'installed'
  }

  service { 'sshd':
    ensure => running,
    enable => true,
  }

  sshd_config { "PermitRootLogin":
    ensure => present,
    value  => "no",
    notify => Service['sshd']
  }
}
