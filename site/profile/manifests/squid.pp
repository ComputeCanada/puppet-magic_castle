class profile::squid::server(
  Integer $port = 3128,
  Integer $cache_size = 4096,
) {
  class { 'squid': }

  squid::acl { 'CLUSTER_NETWORK':
    type    => 'src',
    entries => [profile::getcidr()]
  }

  consul::service { 'squid':
    port    => Integer(keys(lookup('squid::http_ports'))[0]),
    require => Tcp_conn_validator['consul'],
    token   => lookup('profile::consul::acl_api_token'),
  }
}
