class profile::squid::server {
  # GCP instances netmask is set to /32 but the network netmask is available
  if $gce {
    $netmask = $gce['instance']['networkInterfaces'][0]['subnetmask']
  }
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
