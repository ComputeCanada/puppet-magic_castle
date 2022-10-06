class profile::metrics::node_exporter {
  include prometheus::node_exporter
  consul::service { 'node-exporter':
    port  => 9100,
    tags  => ['node-exporter'],
    token => lookup('profile::consul::acl_api_token')
  }
}

class profile::metrics::slurm_job_exporter {
  consul::service { 'slurm-job-exporter':
    port  => 9798,
    tags  => ['slurm-job-exporter'],
    token => lookup('profile::consul::acl_api_token')
  }

  exec { 'pip install prometheus-client':
    command => '/usr/bin/pip3.6 install prometheus-client',
    unless  => '/usr/bin/pip3.6 freeze | /usr/bin/grep prometheus-client',
    before  => Service['slurm-job-exporter'],
  }

  #FIXME need GPUs installed before doing this pip, if not the exporter will crash because libs are missing
  #exec { 'pip install nvidia-ml-py':
  #  command => '/usr/bin/pip3.6 install nvidia-ml-py',
  #  unless  => '/usr/bin/pip3.6 freeze | /usr/bin/grep nvidia-ml-py',
  #  before  => Service['slurm-job-exporter'],
  #}

  package { 'python3-psutil': }
  -> package { 'slurm-job-exporter':
    source   => 'https://github.com/guilbaults/slurm-job-exporter/releases/download/v0.0.8/slurm-job-exporter-0.0.8-1.el8.noarch.rpm',
    provider => 'rpm',
  }
  -> service { 'slurm-job-exporter':
    ensure => 'running',
    enable => true,
  }
}


class profile::metrics::server {
  class { 'prometheus::server':
    version        => '2.39.0',
    scrape_configs => [
      {
        'job_name'          => 'node',
        'scrape_interval'   => '10s',
        'scrape_timeout'    => '10s',
        'honor_labels'      => true,
        'consul_sd_configs' => [{
          'server' => '127.0.0.1:8500',
          'token'  => lookup('profile::consul::acl_api_token')
        }],
        'relabel_configs'   => [
          {
            'source_labels' => ['__meta_consul_tags'],
            'regex'         => '.*,node-exporter,.*',
            'action'        => 'keep'
          },
          {
            'source_labels' => ['__meta_consul_node'],
            'target_label'  => 'instance'
          }
        ],
      },
      {
        'job_name'          => 'slurm_job',
        'scrape_interval'   => '10s',
        'scrape_timeout'    => '10s',
        'honor_labels'      => true,
        'consul_sd_configs' => [{
          'server' => '127.0.0.1:8500',
          'token'  => lookup('profile::consul::acl_api_token')
        }],
        'relabel_configs'   => [
          {
            'source_labels' => ['__meta_consul_tags'],
            'regex'         => '.*,slurm-job-exporter,.*',
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
