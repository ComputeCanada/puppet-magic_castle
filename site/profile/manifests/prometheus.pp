# Configure a Prometheus exporter that exports server usage metrics, for example:
# - CPU usage
# - memory usage
# It should run on every server of the cluster.
class profile::prometheus::node_exporter {
  include prometheus::node_exporter
  @consul::service { 'node_exporter':
    port => 9100,
    tags => ['exporter'],
  }

  # Adding 'mc_bootstrap' to User/Group['node-exporter'] makes sure the
  # puppet user is added to the 'node-exporter' group during the bootstrap
  # phase of the puppetserver, therefore preventing the puppetserver to
  # restart while it serves catalog to other instances.
  User <| title == 'node-exporter' |> {
    tag +> 'mc_bootstrap'
  }
  Group <| title == 'node-exporter' |> {
    tag +> 'mc_bootstrap'
  }

  # In cases where the puppet user exists, we add it to
  # node-exporter group so it can write in /var/lib/node_exporter.
  # If the resource does not exist, the following statement is simply
  # ignored. Puppet needs to be added to node-exporter group before
  # the group of /var/lib/node_exporter is changed from puppet to
  # node-exporter. Otherwise, we risk not being able to write reports
  User <| title == 'puppet' |> {
    groups  +> 'node-exporter',
    before  => File['/var/lib/node_exporter'],
    tag     +> 'mc_bootstrap',
    require +> Group['node-exporter'],
  }

  file { '/var/lib/node_exporter':
    ensure  => directory,
    owner   => 'node-exporter',
    group   => 'node-exporter',
    mode    => '0775',
    require => [
      User['node-exporter'],
      Group['node-exporter'],
    ],
    tag     => ['mc_bootstrap'],
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
class profile::prometheus::slurm_job_exporter (
  String $version,
  String $nvidia_ml_py_version = '11.515.75',
) {
  @consul::service { 'slurm-job-exporter':
    port => 9798,
    tags => ['slurm', 'exporter'],
  }

  $el = $facts['os']['release']['major']
  ensure_packages(['python3'], { ensure => 'present' })
  package { 'python3-prometheus_client':
    require => Yumrepo['epel'],
  }
  package { 'slurm-job-exporter':
    source   => "https://github.com/guilbaults/slurm-job-exporter/releases/download/v${version}/slurm-job-exporter-${version}-1.el${el}.noarch.rpm",
    provider => 'yum',
  }

  if $facts['nvidia_gpu_count'] > 0 and profile::is_grid_vgpu() {
    # Used by slurm-job-exporter to export GPU metrics
    # DCGM does not work with GRID VGPU, most of the stats are missing
    ensure_packages(['python3-pip'], { ensure => 'present' })
    $py3_version = lookup('os::redhat::python3::version')

    exec { 'pip install nvidia-ml-py':
      command => "/usr/bin/pip${py3_version} install --force-reinstall nvidia-ml-py==${nvidia_ml_py_version}",
      creates => "/usr/local/lib/python${py3_version}/site-packages/pynvml.py",
      notify  => Service['slurm-job-exporter'],
      require => [
        Package['python3'],
        Package['python3-pip'],
      ],
    }
  }

  service { 'slurm-job-exporter':
    ensure  => 'running',
    enable  => true,
    require => [
      Package['slurm-job-exporter'],
      Package['python3-prometheus_client'],
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
class profile::prometheus::slurm_exporter (
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
    content => epp('profile/prometheus/prometheus-slurm-exporter.service',
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

class profile::prometheus::apache_exporter {
  include prometheus::apache_exporter
  @consul::service { 'apache_exporter':
    port => 9117,
    tags => ['exporter'],
  }
  File<| title == '/etc/httpd/conf.d/server-status.conf' |>
}

class profile::prometheus::caddy_exporter (Integer $port = 2020) {
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
