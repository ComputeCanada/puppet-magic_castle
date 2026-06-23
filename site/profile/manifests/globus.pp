class profile::globus (
  String[1] $collection_path = '/nfs',
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
    globus-connect-server -F json storage-gateway create \
    --use-explicit-host ${lookup('terraform.self.public_ip')} \
    posix \"${lookup('terraform.data.cluster_name')} \
    gateway\" ${domain_string} > /var/lib/globus-connect-server/gateway.json\n",
  }

  file { '/root/globus-collection-setup':
    ensure    => 'file',
    owner     => 'root',
    group     => 'root',
    mode      => '0700',
    show_diff => false,
    content   => "GCS_CLI_ENDPOINT_ID=$(jq .endpoint_id -r /var/lib/globus-connect-server/info.json)\
    globus-connect-server -F json --use-explicit-host ${lookup('terraform.self.public_ip')} \
    collection create $(jq -r .id /var/lib/globus-connect-server/gateway.json) ${collection_path} \
    --default-directory '\$USER' \
    \"${lookup('terraform.data.cluster_name')} collection\" > /var/lib/globus-connect-server/collection.json\n",
  }

  exec { 'globus-gateway-setup':
    command     => '/bin/sh /root/globus-gateway-setup',
    environment => [
      "GCS_CLI_CLIENT_ID=${globus::client_id}",
      "GCS_CLI_CLIENT_SECRET=${globus::client_secret.unwrap}",
    ],
    unless      => '/bin/test -s /var/lib/globus-connect-server/gateway.json',
    require     => Exec['globus-endpoint-setup'],
  }

  exec { 'globus-collection-setup':
    command     => '/bin/sh /root/globus-collection-setup',
    environment => [
      "GCS_CLI_CLIENT_ID=${globus::client_id}",
      "GCS_CLI_CLIENT_SECRET=${globus::client_secret.unwrap}",
    ],
    unless      => '/bin/test -s /var/lib/globus-connect-server/collection.json',
    require     => Exec['globus-gateway-setup'],
  }
  Firewall <| |> -> Exec['globus-endpoint-setup']
  Mount <| |> -> Exec['globus-collection-setup']
}
