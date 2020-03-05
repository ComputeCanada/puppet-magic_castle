class profile::squid::server (Integer $port = 3128) {
  package { 'squid':
    ensure => 'installed'
  }

  $cidr = profile::getcidr()
  file { '/etc/squid/squid.conf':
    ensure  => 'present',
    content => epp('profile/squid/squid.conf', {'cidr' => $cidr, 'port' => $port})
  }

  service { 'squid':
    ensure    => 'running',
    enable    => true,
    subscribe => File['/etc/squid/squid.conf'],
  }

  consul::service { 'squid':
    port    => $port,
    require => Tcp_conn_validator['consul'],
    token   => lookup('profile::consul::acl_api_token'),
  }
}
