class profile::consul (Array[String] $servers) {
  include consul_template

  $interface = profile::getlocalinterface()
  $ipaddress = $facts['networking']['interfaces'][$interface]['ip']

  if $ipaddress in $servers {
    $is_server = true
    $bootstrap_expect = length($servers)
    $retry_join = $servers.filter | $ip | { $ip != $ipaddress }
  } else {
    $is_server = false
    $bootstrap_expect = 0
    $retry_join = $servers
  }

  class { 'consul':
    config_mode   => '0640',
    acl_api_token => lookup('profile::consul::acl_api_token'),
    config_hash   => {
      'bootstrap_expect' => $bootstrap_expect,
      'bind_addr'        => $ipaddress,
      'data_dir'         => '/opt/consul',
      'log_level'        => 'INFO',
      'node_name'        => $facts['networking']['hostname'],
      'server'           => $is_server,
      'retry_join'       => $retry_join,
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

  if ! $is_server {
    $consul_validators = $servers.map | $index, $server_ip | {
      tcp_conn_validator { "consul-server-${index}":
        host      => $server_ip,
        port      => 8300,
        try_sleep => 5,
        timeout   => 120,
        require   => Service['consul'],
      }
    }
  } else {
    $consul_validators = []
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

  # Ensure consul can read the state of agent_catalog_run.lock
  file { '/opt/puppetlabs/puppet/cache':
    ensure => directory,
    mode   => '0751',
  }

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
