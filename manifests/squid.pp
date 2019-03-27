class profile::squid::server {
  package { "squid":
    ensure => "installed"
  }

  service { 'squid':
    ensure => 'running',
    enable => 'true'
  }

  $cidr = profile::getcidr()
  file { '/etc/squid/squid.conf':
    ensure  => 'present',
    content => epp('profile/squid/squid.conf', {'cidr' => $cidr})
  }
}
