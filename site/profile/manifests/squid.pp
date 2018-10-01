class profile::squid::server {
  $masklen = netmask_to_masklen("$netmask")
  $cidr    = "$network/$masklen"
    
  package { "squid":
    ensure => "installed"
  }

  service { 'squid':
    ensure => 'running',
    enable => 'true'
  }

  file { '/etc/squid/squid.conf':
    ensure  => 'present',
    content => epp('profile/squid/squid.conf', {'cidr' => $cidr})
  }  
}