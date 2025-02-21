class profile::fail2ban (
  Array[String] $ignoreip = [],
) {
  include epel

  class { 'fail2ban' :
    banaction      => 'nftables-multiport',
    iptables_chain => 'input',
    whitelist      => ['127.0.0.1/8', lookup('terraform.network.cidr')] + $ignoreip,
  }

  file_line { 'fail2ban_sshd_recv_disconnect':
    ensure  => present,
    path    => '/etc/fail2ban/filter.d/sshd.conf',
    line    => '            ^Received disconnect from <HOST>%(__on_port_opt)s:\s*11:( Bye Bye)?%(__suff)s$',
    after   => '^mdre-extra\ \=*',
    notify  => Service['fail2ban'],
    require => Class['fail2ban::install'],
  }

  Yumrepo['epel'] -> Class['fail2ban::install']

  selinux::module { 'fail2ban_route':
    ensure    => 'present',
    source_pp => 'puppet:///modules/profile/fail2ban/fail2ban_route.pp',
  }
}
