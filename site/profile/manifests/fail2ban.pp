class profile::fail2ban (
  Array[String] $ignoreip = [],
  Hash $actions = {},
  Hash $filters = {},
  Hash $jails = {},
) {
  include epel

  class { 'fail2ban' :
    ignoreip => ['127.0.0.1/8', profile::getcidr()] + $ignoreip,
  }

  create_resources('fail2ban::filter', $filters.reduce({})|$memo, $filter| { $memo + { $filter[0] => { 'filter_name' => $filter[0], 'filter_content' => $filter[1] } } })
  create_resources('fail2ban::jail',   $jails.reduce({})|$memo, $jail| { $memo + { $jail[0] => { 'jail_name' => $jail[0], 'jail_content' => { $jail[0] => $jail[1] } } } })
  create_resources('fail2ban::action', $actions.reduce({})|$memo, $action| { $memo + { $action[0] => { 'action_name' => $action[0], 'action_content' => $action[1] } } })

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
