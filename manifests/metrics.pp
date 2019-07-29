
class profile::metrics::server {

  class { '::consul':
    version     => '1.5.2',
    config_hash => {
      'bootstrap_expect' => 1,
      'data_dir'         => '/opt/consul',
      'log_level'        => 'INFO',
      'node_name'        => $facts['hostname'],
      'server'           => true,
    }
  }

  tcp_conn_validator { 'consul':
    host      => '127.0.0.1',
    port      => 8500,
    try_sleep => 5,
    timeout   => 60,
    require   => Service['consul']
  }

  class { 'prometheus::server':
    version        => '2.11.1',
    scrape_configs => [
      {
        'job_name'          => 'consul',
        'scrape_interval'   => '10s',
        'scrape_timeout'    => '10s',
        'consul_sd_configs' => [{'server' => '127.0.0.1:8500'}],
        'relabel_configs'   => [
          {
            'source_labels' => ['__meta_consul_tags'],
            'regex'         => '.*,monitor,.*',
            'action'        => 'keep'
          },
          {
            'source_labels' => ['__meta_consul_node'],
            'target_label'  => 'instance'
          }
        ],
      },
    ]
  }

  include prometheus::node_exporter
  consul::service { 'node_exporter':
    port => 9100,
    tags => ['monitor'],
  }
}

class profile::metrics::client(String $server_ip) {
  include prometheus::node_exporter
  class { '::consul':
    version     => '1.5.2',
    config_hash => {
      'data_dir'   => '/opt/consul',
      'log_level'  => 'INFO',
      'node_name'  => $facts['hostname'],
      'retry_join' => [$server_ip]
    }
  }

  tcp_conn_validator { 'consul':
    host      => '127.0.0.1',
    port      => 8500,
    try_sleep => 5,
    timeout   => 60,
    require   => Service['consul']
  }

  consul::service { 'node_exporter':
    port => 9100,
    tags => ['monitor'],
  }
}
