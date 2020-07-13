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

  consul::check { 'squid_free_mem':
    interval   => '30s',
    service_id => 'squid',
    args       => [
      '/bin/sh',
      '-c',
      '/usr/bin/free | awk \'/Mem/{printf($3/$2*100)}\' | awk \'{ print($0); if($1 > 70) exit 1;}\''
    ],
    token      => lookup('profile::consul::acl_api_token'),
  }

}
