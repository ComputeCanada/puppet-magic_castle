class profile::fail2ban {
  package { 'fail2ban-server':
    ensure => present
  }

  service { 'fail2ban':
    ensure  => running,
    enable  => true,
    require => Package['fail2ban-server']
  }

  $cidr = profile::getcidr()
  file { '/etc/fail2ban/jail.local':
    ensure  => present,
    content => epp('profile/fail2ban/jail.local', {'cidr' => $cidr}),
    mode    => '0644',
    require => Package['fail2ban-server'],
    notify  => Service['fail2ban'],
  }

  file { '/etc/fail2ban/filter.d/ssh-ban-root.conf':
    ensure  => present,
    source  => 'puppet:///modules/profile/fail2ban/ssh-ban-root.conf',
    mode    => '0644',
    require => Package['fail2ban-server'],
    notify  => Service['fail2ban'],
  }

  file_line { 'fail2ban_sshd_recv_disconnect':
    ensure => present,
    path   => '/etc/fail2ban/filter.d/sshd.conf',
    line   => '            ^Received disconnect from <HOST>%(__on_port_opt)s:\s*11:( Bye Bye)?%(__suff)s$',
    after  => '^mdre-extra\ \=*',
    notify => Service['fail2ban']
  }
}
