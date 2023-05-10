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
    command => '/usr/bin/pip3.6 install  --force-reinstall prometheus-client==0.15.0',
    creates => '/usr/local/lib/python3.6/site-packages/prometheus_client',
    before  => Service['slurm-job-exporter'],
  }

  # Since slurm-job-exporter is installed without a repo, it will not install
  # the required dependency of python3-psutil from the specfile, so it needs
  # to be installed manually before slurm-job-exporter
  package { 'python3-psutil': }
  -> package { 'slurm-job-exporter':
    source   => 'https://github.com/guilbaults/slurm-job-exporter/releases/download/v0.0.10/slurm-job-exporter-0.0.10-1.el8.noarch.rpm',
    provider => 'rpm',
  }
  -> service { 'slurm-job-exporter':
    ensure => 'running',
    enable => true,
  }
}

class profile::metrics::slurm_exporter {
  consul::service { 'slurm-exporter':
    port  => 8081,
    tags  => ['slurm-exporter'],
    token => lookup('profile::consul::acl_api_token')
  }

  file { '/opt/prometheus-slurm-exporter':
    source => 'https://object-arbutus.cloud.computecanada.ca/userportal-public/prometheus-slurm-exporter',
    owner  => 'slurm',
    group  => 'slurm',
    mode   => '0755',
    notify => Service['prometheus-slurm-exporter'],
  }

  file { '/etc/systemd/system/prometheus-slurm-exporter.service':
    source => 'puppet:///modules/profile/metrics/prometheus-slurm-exporter.service',
    notify => Service['prometheus-slurm-exporter'],
  }

  service { 'prometheus-slurm-exporter':
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
        'consul_sd_configs' => [
          {
            'server' => '127.0.0.1:8500',
            'token'  => lookup('profile::consul::acl_api_token')
          },
        ],
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
        'consul_sd_configs' => [
          {
            'server' => '127.0.0.1:8500',
            'token'  => lookup('profile::consul::acl_api_token'),
          },
        ],
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
      {
        'job_name'          => 'prometheus-slurm-exporter',
        'scrape_interval'   => '10s',
        'scrape_timeout'    => '10s',
        'honor_labels'      => true,
        'consul_sd_configs' => [
          {
            'server' => '127.0.0.1:8500',
            'token'  => lookup('profile::consul::acl_api_token'),
          }
        ],
        'relabel_configs'   => [
          {
            'source_labels' => ['__meta_consul_tags'],
            'regex'         => '.*,slurm-exporter,.*',
            'action'        => 'keep'
          },
          {
            'source_labels' => ['__meta_consul_node'],
            'target_label'  => 'instance'
          }
        ],
      },
    ],
  }
}
