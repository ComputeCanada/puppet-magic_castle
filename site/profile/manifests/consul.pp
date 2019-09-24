class profile::consul::server {
  class { '::consul':
    version     => '1.5.2',
    config_hash => {
      'bootstrap_expect' => 1,
      'data_dir'         => '/opt/consul',
      'log_level'        => 'INFO',
      'node_name'        => $facts['hostname'],
      'server'           => true,
      'acl' => {
        'enabled'        => true,
        'default_policy' => 'deny',
        'tokens'         => {
          'master' => lookup('profile::consul::acl_api_token')
        }
      }
    }
  }

  tcp_conn_validator { 'consul':
    host      => '127.0.0.1',
    port      => 8500,
    try_sleep => 5,
    timeout   => 60,
    require   => Service['consul']
  }
}

class profile::consul::client(String $server_ip) {
  class { '::consul':
    version     => '1.5.2',
    config_hash => {
      'data_dir'   => '/opt/consul',
      'log_level'  => 'INFO',
      'node_name'  => $facts['hostname'],
      'retry_join' => [$server_ip]
    }
  }

  tcp_conn_validator { 'consul-server':
    host      => $server_ip,
    port      => 8300,
    try_sleep => 5,
    timeout   => 120,
    require   => Service['consul']
  }

  tcp_conn_validator { 'consul':
    host      => '127.0.0.1',
    port      => 8500,
    try_sleep => 5,
    timeout   => 60,
    require   => [Service['consul'],
                  Tcp_conn_validator['consul-server']]
  }
}
