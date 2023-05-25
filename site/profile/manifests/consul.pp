class profile::consul::server {
  $interface = profile::getlocalinterface()
  $ipaddress = $facts['networking']['interfaces'][$interface]['ip']
  $consul_servers = lookup('profile::consul::client::servers', undef, undef, [$ipaddress])

  class { 'consul':
    config_mode   => '0640',
    acl_api_token => lookup('profile::consul::acl_api_token'),
    config_hash   => {
      'bootstrap_expect' => length($consul_servers),
      'bind_addr'        => $ipaddress,
      'data_dir'         => '/opt/consul',
      'log_level'        => 'INFO',
      'node_name'        => $facts['networking']['hostname'],
      'server'           => true,
      'retry_join'       => $consul_servers.filter | $ip | { $ip != $ipaddress },
      'acl'              => {
        'enabled'        => true,
        'default_policy' => 'deny',
        'tokens'         => {
          'initial_management' => lookup('profile::consul::acl_api_token'),
          'agent'              => lookup('profile::consul::acl_api_token'),
        },
      },
    },
  }

  tcp_conn_validator { 'consul':
    host      => '127.0.0.1',
    port      => 8500,
    try_sleep => 5,
    timeout   => 60,
    require   => Service['consul'],
  }

  include profile::consul::puppet_watch
}

class profile::consul::client (Array[String] $servers) {
  $interface = profile::getlocalinterface()
  $ipaddress = $facts['networking']['interfaces'][$interface]['ip']

  class { 'consul':
    config_mode => '0640',
    config_hash => {
      'bind_addr'  => $ipaddress,
      'data_dir'   => '/opt/consul',
      'log_level'  => 'INFO',
      'node_name'  => $facts['networking']['hostname'],
      'retry_join' => $servers,
      'acl'        => {
        'tokens' => {
          'agent' => lookup('profile::consul::acl_api_token'),
        },
      },
    },
  }

  $consul_validators = $servers.map | $index, $server_ip | {
    tcp_conn_validator { "consul-server-${index}":
      host      => $server_ip,
      port      => 8300,
      try_sleep => 5,
      timeout   => 120,
      require   => Service['consul'],
    }
  }

  tcp_conn_validator { 'consul':
    host      => '127.0.0.1',
    port      => 8500,
    try_sleep => 5,
    timeout   => 60,
    require   => [Service['consul']] + $consul_validators,
  }

  include profile::consul::puppet_watch
}

class profile::consul::puppet_watch {
  # jq can be used to easily retrieve the token from
  # consul config file like this:
  # jq -r .acl_agent_token /etc/consul/config.json
  include epel
  ensure_packages(['jq'], { ensure => 'present', require => Yumrepo['epel'] })

  $consul_sudoer = "consul ALL=(root) NOPASSWD: /usr/bin/systemctl reload puppet\n"
  file { '/etc/sudoers.d/99-consul':
    owner   => 'root',
    group   => 'root',
    mode    => '0440',
    content => $consul_sudoer,
  }

  file { '/usr/bin/puppet_event_handler.sh':
    mode   => '0755',
    owner  => 'root',
    group  => 'root',
    source => 'puppet:///modules/profile/consul/puppet_event_handler.sh',
  }

  consul::watch { 'puppet_event':
    ensure     => present,
    type       => 'event',
    event_name => 'puppet',
    args       => ['/usr/bin/puppet_event_handler.sh'],
    token      => lookup('profile::consul::acl_api_token'),
  }
}
