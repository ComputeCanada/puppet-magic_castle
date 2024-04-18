class profile::vector
(
  String $config = file('puppet:///modules/profile/vector/default_config.yaml'),
  Boolean $access_var_log = false,
)
{
  yumrepo { 'vector':
    ensure        => present,
    enabled       => true,
    baseurl       => "https://yum.vector.dev/stable/vector-0/${::facts['architecture']}/",
    gpgcheck      => 1,
    gpgkey        => [
      'https://keys.datadoghq.com/DATADOG_RPM_KEY_CURRENT.public',
      'https://keys.datadoghq.com/DATADOG_RPM_KEY_B01082D3.public',
      'https://keys.datadoghq.com/DATADOG_RPM_KEY_FD4BF915.public',
    ],
    repo_gpgcheck => 1,
  }

  package { 'vector':
    ensure  => 'installed',
    require => [Yumrepo['vector']],
  }

  service { 'vector':
    ensure  => running,
    enable  => true,
    require => [Package['vector']],
  }

  file { '/etc/vector/vector.yaml':
    notify  => Service['vector'],
    content => $config,
    require => [Package['vector']],
  }

  if $access_var_log {
    file { '/var/log':
      ensure  => directory,
      group   => 'vector',
      recurse => true,
      notify  => Service['vector'],
      require => [Package['vector']],
    }
  }
}

