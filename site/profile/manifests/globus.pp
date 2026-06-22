class profile::globus (
  Array[String] $domains = ['globus.org']
) {
  package { 'wget':
    ensure => installed,
  }
  include globus
  Package['wget'] -> Class['globus']

  $domain_string = $domains.map|$value| { " --domain ${value}" }.join(' ')
  file { '/root/globus-gateway-setup':
    ensure    => 'file',
    owner     => 'root',
    group     => 'root',
    mode      => '0700',
    show_diff => false,
    content   => "GCS_CLI_ENDPOINT_ID=$(jq .endpoint_id -r /var/lib/globus-connect-server/info.json) \
    globus-connect-server -F json storage-gateway create posix \"${lookup('terraform.data.cluster_name')} \
    gateway\" ${domain_string} > /var/lib/globus-connect-server/gateway.json\n",
  }

  file { '/root/globus-collection-setup':
    ensure    => 'file',
    owner     => 'root',
    group     => 'root',
    mode      => '0700',
    show_diff => false,
    content   => "GCS_CLI_ENDPOINT_ID=$(jq .endpoint_id -r /var/lib/globus-connect-server/info.json)\
    globus-connect-server -F json collection create $(jq -r .id /var/lib/globus-connect-server/gateway.json) / \
    \"${lookup('terraform.data.cluster_name')} collection\" > /var/lib/globus-connect-server/collection.json\n",
  }

  exec { 'globus-setup-gateway':
    command     => '/bin/sh /root/globus-gateway-setup',
    environment => Sensitive([
        "GCS_CLI_CLIENT_ID=${globus::client_id}",
        "GCS_CLI_CLIENT_SECRET=${globus::client_secret.unwrap}",
    ]),
    creates     => '/var/lib/globus-connect-server/gateway.json',
    require     => Exec['globus-endpoint-setup'],
  }

  exec { 'globus-setup-collection':
    command     => '/bin/sh /root/globus-collection-setup',
    environment => Sensitive([
        "GCS_CLI_CLIENT_ID=${globus::client_id}",
        "GCS_CLI_CLIENT_SECRET=${globus::client_secret.unwrap}",
    ]),
    creates     => '/var/lib/globus-connect-server/collection.json',
    require     => Exec['globus-gateway-setup'],
  }
}
