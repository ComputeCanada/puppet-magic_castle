class profile::firewall {
  tag 'mc_bootstrap'
  class { 'nftables':
    out_all        => true,
    noflush_tables => ['inet-f2b-table'],
  }

  # Do not let user get access to cloud-init metadata server as it could
  # include sensitive information.
  nftables::rule { 'default_out-drop_metadata':
    content => 'ip daddr 169.254.169.254 skuid != 0 drop comment "Drop metadata server"',
    order   => '89',
  }
}
