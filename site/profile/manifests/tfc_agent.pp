class profile::tfc_agent (
  String $token,
  String $agent_name,
  String $version = '1.28.8',
) {
  $architecture = $facts['os']['architecture'] ? {
    'x86_64'  => 'amd64',
    'aarch64' => 'arm64',
    default   => $facts['os']['architecture'],
  }

  $install_dir  = '/var/lib/tfc-agent'
  $version_dir  = "${install_dir}/${version}"
  $etc_dir      = '/etc/tfc-agent'
  $env_file     = "${etc_dir}/tfc-agent.env"
  $service_file = '/etc/systemd/system/tfc-agent.service'
  $archive_file = "/opt/puppetlabs/puppet/cache/puppet-archive/tfc-agent_${version}_linux_${architecture}.zip"
  $archive_url  = "https://releases.hashicorp.com/tfc-agent/${version}/tfc-agent_${version}_linux_${architecture}.zip"

  ensure_resource('file', '/opt/puppetlabs/puppet/cache/puppet-archive', { 'ensure' => 'directory' })

  file { [$install_dir, $version_dir, $etc_dir]:
    ensure => 'directory',
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  archive { 'tfc-agent':
    path         => $archive_file,
    source       => $archive_url,
    extract      => true,
    extract_path => $version_dir,
    creates      => "${version_dir}/tfc-agent",
    require      => [
      File['/opt/puppetlabs/puppet/cache/puppet-archive'],
      File[$version_dir],
    ],
  }

  file { "${install_dir}/tfc-agent":
    ensure  => 'link',
    target  => "${version_dir}/tfc-agent",
    owner   => 'root',
    group   => 'root',
    require => Archive['tfc-agent'],
    notify  => Service['tfc-agent'],
  }

  file { $service_file:
    ensure  => 'file',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('profile/tfc_agent/tfc-agent.service.epp',
      {
        env_file    => $env_file,
        install_dir => $install_dir,
      }
    ),
    notify  => Service['tfc-agent'],
  }

  file { $env_file:
    ensure    => 'file',
    owner     => 'root',
    group     => 'root',
    mode      => '0600',
    show_diff => false,
    content   => epp('profile/tfc_agent/tfc-agent.env.epp',
      {
        token      => $token,
        agent_name => $agent_name,
      }
    ),
    require   => File[$etc_dir],
    notify    => Service['tfc-agent'],
  }

  service { 'tfc-agent':
    ensure  => 'running',
    enable  => true,
    require => [
      File["${install_dir}/tfc-agent"],
      File[$env_file],
      File[$service_file],
    ],
  }
}
