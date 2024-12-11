class profile::firewall::pre {
  Firewall {
    require => undef,
  }

  # Default firewall rules
  firewall { '000 accept all icmp':
    proto => 'icmp',
    jump  => 'accept',
  }
  -> firewall { '001 accept all to lo interface':
    proto   => 'all',
    iniface => 'lo',
    jump    => 'accept',
  }
  -> firewall { '002 reject local traffic not on loopback interface':
    iniface     => '! lo',
    proto       => 'all',
    destination => '127.0.0.1/8',
    jump        => 'reject',
  }
  -> firewall { '003 accept related established rules':
    proto => 'all',
    state => ['RELATED', 'ESTABLISHED'],
    jump  => 'accept',
  }
}

class profile::firewall {
  tag 'mc_bootstrap'

  Firewall {
    before  => Class['profile::firewall::post'],
    require => Class['profile::firewall::pre'],
  }

  class { 'firewall': }
  -> class {['profile::firewall::pre', 'profile::firewall::post']: }

  firewall { '004 accept all from local network':
    chain  => 'INPUT',
    proto  => 'all',
    source => profile::getcidr(),
    jump   => 'accept',
  }

  firewall { '005 drop access to metadata server':
    chain       => 'OUTPUT',
    proto       => 'tcp',
    destination => '169.254.169.254',
    jump        => 'drop',
    uid         => '! root',
  }
}

class profile::firewall::post {
  firewall { '999 drop all':
    proto  => 'all',
    jump   => 'drop',
    before => undef,
  }
}
