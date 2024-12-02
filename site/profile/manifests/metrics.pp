# Configure a Prometheus exporter that exports server usage metrics, for example:
# - CPU usage
# - memory usage
# It should run on every server of the cluster.
class profile::metrics::node_exporter {
  include profile::consul
  include prometheus::node_exporter
  consul::service { 'node-exporter':
    port  => 9100,
    tags  => ['node-exporter'],
    token => lookup('profile::consul::acl_api_token'),
  }
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
  include profile::consul

  consul::service { 'slurm-job-exporter':
    port  => 9798,
    tags  => ['slurm-job-exporter'],
    token => lookup('profile::consul::acl_api_token'),
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
    ],
  }
}

# Configure a Prometheus exporter that exports the Slurm scheduling metrics, for example:
# - allocated nodes
# - allocated gpus
# - pending jobs
# - completed jobs
# This exporter typically runs on the Slurm controller server, but it can run on any server
# with a functional Slurm command-line installation.
class profile::metrics::slurm_exporter {
  include profile::consul

  consul::service { 'slurm-exporter':
    port  => 8081,
    tags  => ['slurm-exporter'],
    token => lookup('profile::consul::acl_api_token'),
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
    source => 'puppet:///modules/profile/metrics/prometheus-slurm-exporter.service',
    notify => Service['prometheus-slurm-exporter'],
  }

  service { 'prometheus-slurm-exporter':
    ensure  => 'running',
    enable  => true,
    require => [
      Package['prometheus-slurm-exporter'],
      File['/etc/systemd/system/prometheus-slurm-exporter.service'],
    ],
  }
}
