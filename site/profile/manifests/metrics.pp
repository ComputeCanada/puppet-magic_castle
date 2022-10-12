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
    content => '[Unit]
Description=Exporter for slurm stats
After=network.target

[Service]
User=slurm
Group=slurm
Type=simple
ExecStart=/opt/prometheus-slurm-exporter --collector.partition --listen-address=":8081"
PIDFile=/var/run/prometheus-slurm-exporter/prometheus-slurm-exporter.pid
KillMode=process
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/opt/puppetlabs/bin:/opt/software/slurm/bin:/root/bin
Restart=always

[Install]
WantedBy=multi-user.target',
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
      {
        'job_name'          => 'prometheus-slurm-exporter',
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
            'regex'         => '.*,slurm-exporter,.*',
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
