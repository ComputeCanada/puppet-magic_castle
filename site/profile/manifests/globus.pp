class profile::globus {
  package { 'wget':
    ensure => installed,
  }
  include globus
  Package['wget'] -> Class['globus']

  firewall { '200 globus public':
    chain  => 'INPUT',
    dport  => [443],
    proto  => 'tcp',
    source => '0.0.0.0/0',
    action => 'accept',
  }

  firewall { '201 gridftp':
    chain  => 'INPUT',
    dport  => '50000:51000',
    proto  => 'tcp',
    source => '0.0.0.0/0',
    action => 'accept',
  }
}
