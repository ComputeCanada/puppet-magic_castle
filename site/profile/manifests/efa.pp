class profile::efa {
  package { 'libibverbs-utils':
    ensure => 'installed',
  }

  package { 'rdma-core-devel':
    ensure => 'installed',
  }

  package { 'librdmacm-utils':
    ensure => 'installed',
  }

  exec { 'download-efa-driver':
    command => 'curl -O https://efa-installer.amazonaws.com/aws-efa-installer-1.30.0.tar.gz && tar -xf aws-efa-installer-1.30.0.tar.gz && cd aws-efa-installer',
    cwd     => '/tmp',
    creates => '/tmp/aws-efa-installer',
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
  }

  exec { 'install-efa-driver':
    command => 'bash efa_installer.sh -y',
    cwd     => '/tmp/aws-efa-installer',
    require => [
      Exec['download-efa-driver'],
      Package['libibverbs-utils'],
      Package['rdma-core-devel'],
      Package['librdmacm-utils'],
    ],
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    creates => '/opt/amazon/efa',
  }

  tidy { 'delete-efa-driver':
    path    => '/tmp',
    recurse => true,
    matches => [ 'aws-efa-installer*' ],
    rmdirs  => true,
    require => Exec['install-efa-driver'],
  }
}
