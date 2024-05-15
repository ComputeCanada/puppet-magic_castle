class profile::efa (
  String $version = 'latest'
) {
  package { 'libibverbs-utils':
    ensure => 'installed',
  }

  package { 'rdma-core-devel':
    ensure => 'installed',
  }

  package { 'librdmacm-utils':
    ensure => 'installed',
  }

  archive { 'download-efa-driver':
    path         => "/opt/puppetlabs/puppet/cache/puppet-archive/aws-efa-installer-${version}.tar.gz",
    extract      => true,
    extract_path => '/tmp/',
    source       => "https://efa-installer.amazonaws.com/aws-efa-installer-${version}.tar.gz"
  }

  exec { 'install-efa-driver':
    command => 'bash efa_installer.sh -y --minimal && rm -rf /tmp/aws-efa-installer',
    cwd     => '/tmp/aws-efa-installer',
    require => [
      Archive['download-efa-driver'],
      Package['libibverbs-utils'],
      Package['rdma-core-devel'],
      Package['librdmacm-utils'],
    ],
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    creates => '/etc/modprobe.d/efa.conf',
  }

  kmod::load { 'efa':
    require => Exec['install-efa-driver']
  }

  selinux::module { 'efa':
    ensure    => 'present',
    source_pp => 'puppet:///modules/profile/efa/efa.pp',
  }
}
