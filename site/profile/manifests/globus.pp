# Extends treydock-globus with a POSIX storage gateway, a collection,
# and optional local OpenID Connect authentication for cluster users.
#
# Gateway, collection, and OIDC setup are intentionally one-time
# operations guarded by JSON state files in /var/lib/globus-connect-server.
# Changing parameters such as domains, collection_path, or OIDC settings
# after setup requires removing the affected Globus service and its
# corresponding JSON state file before the next Puppet run.
class profile::globus (
  String[1] $collection_path = '/nfs',
  Array[String] $domains = [],
  Boolean $enable_oidc = true,
  Optional[Array[Hash]] $identity_mapping = undef,
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
    content   => epp(
      'profile/globus/globus-gateway-setup',
      {
        'public_ip'        => lookup('terraform.self.public_ip'),
        'cluster_name'     => lookup('terraform.data.cluster_name'),
        'domain_string'    => $domain_string,
        'identity_mapping' => $identity_mapping != undef,
      }
    ),
  }

  file { '/root/globus-collection-setup':
    ensure    => 'file',
    owner     => 'root',
    group     => 'root',
    mode      => '0700',
    show_diff => false,
    content   => epp(
      'profile/globus/globus-collection-setup',
      {
        'public_ip'       => lookup('terraform.self.public_ip'),
        'cluster_name'    => lookup('terraform.data.cluster_name'),
        'collection_path' => $collection_path,
      }
    ),
  }

  $domain_name = lookup('terraform.data.domain_name')
  file { '/root/globus-oidc-setup':
    ensure    => 'file',
    owner     => 'root',
    group     => 'root',
    mode      => '0700',
    show_diff => false,
    content   => epp(
      'profile/globus/globus-oidc-setup',
      {
        'domain_name' => $domain_name,
      }
    ),
  }

  if $identity_mapping {
    file { '/etc/globus/identity_mapping.json':
      ensure  => 'file',
      owner   => 'root',
      group   => 'root',
      mode    => '0700',
      content => to_json({ 'DATA_TYPE' => 'expression_identity_mapping#1.0.0', 'mappings' => $identity_mapping }),
    }
  }

  if $ensure_oidc == 'stopped' and length($domains) == 0 {
    fail('Globus requires at least one authentication domain or ensure OIDC server is running  (profile::globus::ensure_oidc: running)')
  }

  exec { 'globus-gateway-setup':
    command     => '/bin/sh /root/globus-gateway-setup',
    environment => [
      "GCS_CLI_CLIENT_ID=${globus::client_id}",
      "GCS_CLI_CLIENT_SECRET=${globus::client_secret.unwrap}",
    ],
    unless      => '/bin/test -s /var/lib/globus-connect-server/gateway.json',
    require     => [
      Exec['globus-endpoint-setup'],
      File['/root/globus-gateway-setup'],
    ],
  }

  exec { 'globus-collection-setup':
    command     => '/bin/sh /root/globus-collection-setup',
    environment => [
      "GCS_CLI_CLIENT_ID=${globus::client_id}",
      "GCS_CLI_CLIENT_SECRET=${globus::client_secret.unwrap}",
    ],
    unless      => '/bin/test -s /var/lib/globus-connect-server/collection.json',
    require     => [
      Exec['globus-gateway-setup'],
      File['/root/globus-collection-setup'],
    ],
  }

  if $enable_oidc {
    exec { 'globus-oidc-setup':
      command     => '/bin/sh /root/globus-oidc-setup',
      environment => [
        "GCS_CLI_CLIENT_ID=${globus::client_id}",
        "GCS_CLI_CLIENT_SECRET=${globus::client_secret.unwrap}",
      ],
      unless      => '/bin/test -s /var/lib/globus-connect-server/oidc.json',
      require     => [
        Exec['globus-endpoint-setup'],
        File['/root/globus-oidc-setup'],
      ],
      before      => Exec['globus-gateway-setup'],
    }
    file { '/var/lib/globusoidc/globus-oidc/site/login.mako':
      ensure  => file,
      content => epp('profile/globus/login.mako', {}),
      mode    => '0544',
      owner   => 'globusoidc',
      group   => 'globusoidc',
      require => Exec['globus-oidc-setup'],
    }
  }

  Firewall <| |> -> Exec['globus-endpoint-setup']
  Mount <| |> -> Exec['globus-collection-setup']
}
