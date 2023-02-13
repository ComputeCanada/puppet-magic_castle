class profile::squid::server (
  Integer $port,
  Integer $cache_size,
  Array[String] $cvmfs_acl_regex,
) {
  class { 'squid': }
  squid::http_port { String($port): }
  squid::acl { 'SSL_ports':
    type    => 'port',
    entries => ['443'],
  }
  squid::acl { 'Safe_ports':
    type    => 'port',
    entries => ['80', '443', '1025-65535'],
  }
  squid::acl { 'CONNECT':
    type    => 'method',
    entries => ['CONNECT'],
  }
  squid::acl { 'CLUSTER_NETWORK':
    type    => 'src',
    entries => [profile::getcidr()],
  }
  # How can we have multiple regex entries under the same ACL name?
  # From Squid documentation:
  # You can put different values for the same ACL name on different lines.
  # Squid combines them into one list.
  squid::acl { 'CVMFS':
    type    => 'dstdom_regex',
    entries => $cvmfs_acl_regex,
  }
  squid::http_access { 'manager localhost':
    action => 'allow',
  }
  squid::http_access { 'manager':
    action => 'deny',
  }
  squid::http_access { '!Safe_ports':
    action => 'deny',
  }
  squid::http_access { 'CONNECT !SSL_ports':
    action => 'deny',
  }
  squid::http_access { 'localhost':
    action => 'allow',
  }
  squid::http_access { 'all':
    action => 'deny',
  }
  squid::http_access { 'CLUSTER_NETWORK CVMFS':
    action => 'allow',
  }
  squid::cache_dir { '/var/spool/squid':
    type    => 'ufs',
    options => "${cache_size} 16 256",
  }
  squid::extra_config_section { 'log':
    config_entries => {
      cache_store_log => '/var/log/squid/store.log',
      cache_log       => '/var/log/squid/cache.log',
    },
  }
  squid::refresh_pattern { '.':
    min     => 0,
    max     => 4320,
    percent => 20,
  }

  consul::service { 'squid':
    port    => $port,
    require => Tcp_conn_validator['consul'],
    token   => lookup('profile::consul::acl_api_token'),
  }
}
