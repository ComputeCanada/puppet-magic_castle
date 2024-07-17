class profile::vector
(
  String $config = file('puppet:///modules/profile/vector/default_config.yaml')
)
{
  yumrepo { 'vector':
    ensure        => present,
    enabled       => true,
    baseurl       => "https://yum.vector.dev/stable/vector-0/${::facts['architecture']}/",
    gpgcheck      => 1,
    gpgkey        => [
      'https://yum.vector.dev/DATADOG_RPM_KEY_CURRENT.public',
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
}

