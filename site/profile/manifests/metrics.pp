class profile::metrics::exporter {
  include prometheus::node_exporter
  consul::service { 'node_exporter':
    port => 9100,
    tags => ['monitor'],
  }
}

class profile::metrics::server {
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
}
