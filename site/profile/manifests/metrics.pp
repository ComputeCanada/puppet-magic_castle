# Configure a Prometheus exporter that exports server usage metrics, for example:
# - CPU usage
# - memory usage
# It should run on every server of the cluster.
class profile::metrics::node_exporter {
  include prometheus::node_exporter
  @consul::service { 'node_exporter':
    port => 9100,
    tags => ['exporter'],
  }

  file { '/var/lib/node_exporter':
    ensure => directory,
    owner  => 'node-exporter',
    group  => 'node-exporter',
    mode   => '0775',
  }

  # In cases where the puppet user exists, we add it to
  # node-exporter group so it can write in /var/lib/node_exporter.
  # If the resource does not exist, the following statement is simply
  # ignored.
  User <| title == 'puppet' |> { groups +> 'node-exporter' }
}

# Configure a Prometheus exporter that exports the Slurm compute node metrics, for example:
# - job memory usage
# - job memory max
# - job memory limit
# - job core usage total
# - job process count
# - job threads count
# - job power gpu
# This exporter needs to run on compute nodes.
# @param version The version of the slurm job exporter to install
class profile::metrics::slurm_job_exporter (String $version = '0.3.0') {
  @consul::service { 'slurm-job-exporter':
    port => 9798,
    tags => ['slurm', 'exporter'],
  }

  $el = $facts['os']['release']['major']
  package { 'python3-prometheus_client':
    require => Yumrepo['epel'],
  }
  package { 'slurm-job-exporter':
    source   => "https://github.com/guilbaults/slurm-job-exporter/releases/download/v${version}/slurm-job-exporter-${version}-1.el${el}.noarch.rpm",
    provider => 'yum',
  }

  service { 'slurm-job-exporter':
    ensure  => 'running',
    enable  => true,
    require => [
      Package['slurm-job-exporter'],
      Package['python3-prometheus_client'],
      Service['slurmd'],
    ],
  }

  @exec { 'stop_slurm-job-exporter':
    command     => 'systemctl stop slurm-job-exporter',
    onlyif      => 'systemctl is-active slurm-job-exporter',
    refreshonly => true,
    path        => ['/usr/bin'],
  }
}

# Configure a Prometheus exporter that exports the Slurm scheduling metrics, for example:
# - allocated nodes
# - allocated gpus
# - pending jobs
# - completed jobs
# This exporter typically runs on the Slurm controller server, but it can run on any server
# with a functional Slurm command-line installation.
class profile::metrics::slurm_exporter (
  Integer $port = 8081,
  Array[String] $collectors = ['partition'],
) {
  @consul::service { 'slurm-exporter':
    port => $port,
    tags => ['slurm', 'exporter'],
  }

  $slurm_exporter_url = 'https://download.copr.fedorainfracloud.org/results/cmdntrf/prometheus-slurm-exporter/'
  yumrepo { 'prometheus-slurm-exporter-copr-repo':
    enabled             => true,
    descr               => 'Copr repo for prometheus-slurm-exporter owned by cmdntrf',
    baseurl             => "${slurm_exporter_url}/epel-\$releasever-\$basearch/",
    skip_if_unavailable => true,
    gpgcheck            => 1,
    gpgkey              => "${slurm_exporter_url}/pubkey.gpg",
    repo_gpgcheck       => 0,
  }
  -> package { 'prometheus-slurm-exporter': }

  file { '/etc/systemd/system/prometheus-slurm-exporter.service':
    content => epp('profile/metrics/prometheus-slurm-exporter.service',
      {
        port       => $port,
        collectors => $collectors.map |$collector| { "--collector.${collector}" }.join(' '),
      }
    ),
    notify  => Service['prometheus-slurm-exporter'],
  }

  service { 'prometheus-slurm-exporter':
    ensure  => 'running',
    enable  => true,
    require => [
      Package['prometheus-slurm-exporter'],
      Package['slurm'],
      File['/etc/systemd/system/prometheus-slurm-exporter.service'],
    ],
  }
}

class profile::metrics::apache_exporter {
  include prometheus::apache_exporter
  @consul::service { 'apache_exporter':
    port => 9117,
    tags => ['exporter'],
  }
  File<| title == '/etc/httpd/conf.d/server-status.conf' |>
}

class profile::metrics::caddy_exporter (Integer $port = 2020) {
  include profile::consul
  @consul::service { 'caddy_exporter':
    port => $port,
    tags => ['exporter'],
  }

  $caddy_metrics_content = @("EOT")
    :${port} {
      metrics
    }
    | EOT
  file { '/etc/caddy/conf.d/local_metrics.conf':
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    seltype => 'httpd_config_t',
    require => Package['caddy'],
    content => $caddy_metrics_content,
  }
}
