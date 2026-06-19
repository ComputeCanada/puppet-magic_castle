class profile::globus (
  Array[String] $domains = ['globus.org']
) {
  package { 'wget':
    ensure => installed,
  }
  include globus
  Package['wget'] -> Class['globus']

  firewall { '200 globus public':
    chain  => 'INPUT',
    dport  => [443],
    proto  => 'tcp',
    source => '0.0.0.0/0',
    action => 'accept',
  }

  firewall { '201 gridftp':
    chain  => 'INPUT',
    dport  => '50000-51000',
    proto  => 'tcp',
    source => '0.0.0.0/0',
    action => 'accept',
  }

  $domain_string = $domains.map|$value| { " --domain ${value}" }.join(' ')
  file { '/root/globus-gateway-setup':
    ensure    => 'file',
    owner     => 'root',
    group     => 'root',
    mode      => '0700',
    show_diff => false,
    content   => "GCS_CLI_ENDPOINT_ID=$(jq .endpoint_id -r /var/lib/globus-connect-server/info.json) \
    globus-connect-server -F json storage-gateway create posix \"${lookup('terraform.data.cluster_name')} \
    gateway\" ${domain_string} > /var/lib/globus-connect-server/gateway.json",
  }

  file { '/root/globus-collection-setup':
    ensure    => 'file',
    owner     => 'root',
    group     => 'root',
    mode      => '0700',
    show_diff => false,
    content   => "GCS_CLI_ENDPOINT_ID=$(jq .endpoint_id -r /var/lib/globus-connect-server/info.json)\
    globus-connect-server -F json collection create $(jq -r .id /var/lib/globus-connect-server/gateway.json) / \
    \"${lookup('terraform.data.cluster_name')} collection\" > /var/lib/globus-connect-server/collection.json",
  }

  # exec { 'globus-setup-gateway':
  #   command     => 'sh /root/globus-gateway-setup',
  #   environment => [
  #     "GCS_CLI_CLIENT_ID=${globus::client_id}",
  #     "GCS_CLI_CLIENT_SECRET=${globus::client_secret}",
  #   ],
  #   creates     => '/var/lib/globus-connect-server/gateway.json',
  #   require     => Exec['globus-endpoint-setup'],
  # }
  # exec { 'globus-setup-collection':
  #   command     => 'sh /root/globus-collection-setup',
  #   environment => [
  #     "GCS_CLI_CLIENT_ID=${globus::client_id}",
  #     "GCS_CLI_CLIENT_SECRET=${globus::client_secret}",
  #   ],
  #   creates     => '/var/lib/globus-connect-server/collection.json',
  #   require     => Exec['globus-gateway-setup'],
  # }
}
