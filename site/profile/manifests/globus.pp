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
  Boolean $freeipa_mapping = false,
) {
  if $freeipa_mapping and $identity_mapping != undef {
    fail('freeipa_mapping and identity_mapping are mutually exclusive')
  }

  stdlib::ensure_packages(['wget'], { ensure => 'present' })
  stdlib::ensure_packages(['jq'], { ensure => 'present', require => Yumrepo['epel'] })

  include globus
  Package['wget'] -> Class['globus']

  $display_name = lookup('globus::display_name')
  $domain_name = lookup('terraform.data.domain_name')
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
        'display_name'     => $display_name,
        'domain_string'    => $domain_string,
        'identity_mapping' => $identity_mapping != undef or $freeipa_mapping,
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
        'display_name'    => $display_name,
        'collection_path' => $collection_path,
      }
    ),
  }

  file { '/root/globus-oidc-setup':
    ensure    => 'file',
    owner     => 'root',
    group     => 'root',
    mode      => '0700',
    show_diff => false,
    content   => epp(
      'profile/globus/globus-oidc-setup',
      {
        'display_name' => $display_name,
        'domain_name'  => $domain_name,
      }
    ),
  }

  if $freeipa_mapping {
    include profile::globus::keytab

    file { '/usr/local/bin/globus-freeipa-map':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      seltype => 'bin_t',
      source  => 'puppet:///modules/profile/globus/globus-freeipa-map.py',
      before  => Exec['globus-gateway-setup'],
    }

    $ipa_domain = lookup('profile::freeipa::base::ipa_domain')
    $fqdn = "${facts['networking']['hostname']}.${ipa_domain}"
    $principal = "gcsweb/${fqdn}@${upcase($ipa_domain)}"

    file { '/etc/globus/freeipa-mapping.json':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => stdlib::to_json_pretty({
          'principal' => $principal,
          'keytab'    => '/etc/globus/gcsweb.keytab',
      }),
      require => Exec['globus-node-setup'],
      before  => Exec['globus-gateway-setup'],
    }
    $mapping_document = {
      'DATA_TYPE' => 'external_identity_mapping#1.0.0',
      'command'   => ['/usr/local/bin/globus-freeipa-map'],
    }

    Class['profile::globus::keytab'] -> Exec['globus-gateway-setup']
  } else {
    $mapping_document = { 'DATA_TYPE' => 'expression_identity_mapping#1.0.0', 'mappings' => $identity_mapping }
  }

  if $identity_mapping or $freeipa_mapping {
    file { '/etc/globus/identity_mapping.json':
      ensure  => 'file',
      owner   => 'root',
      group   => 'root',
      mode    => '0700',
      content => stdlib::to_json_pretty($mapping_document),
      require => Exec['globus-node-setup'],
      before  => Exec['globus-gateway-setup'],
    }
  }

  if $enable_oidc == false and length($domains) == 0 {
    fail('Globus requires at least one authentication domain or ensure OIDC server is running  (profile::globus::enable_oidc: true)')
  }

  exec { 'globus-gateway-setup':
    command     => '/bin/sh /root/globus-gateway-setup',
    environment => [
      "GCS_CLI_CLIENT_ID=${globus::client_id}",
      "GCS_CLI_CLIENT_SECRET=${globus::client_secret.unwrap}",
    ],
    unless      => '/bin/test -s /var/lib/globus-connect-server/gateway.json',
    require     => [
      Package['jq'],
      Exec['globus-node-setup'],
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
      Package['jq'],
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
        Exec['globus-node-setup'],
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

# Provision the mapper's service principal, permissions, and keytab.
class profile::globus::keytab {
  $ipa_domain = lookup('profile::freeipa::base::ipa_domain')
  $fqdn = "${facts['networking']['hostname']}.${ipa_domain}"
  $role_name = 'Globus FreeIPA identity mapping'

  profile::freeipa::service_keytab { 'globus':
    service_name      => "gcsweb/${fqdn}",
    config_path       => '/etc/globus/ipa_register_service.json',
    keytab_path       => '/etc/globus/gcsweb.keytab',
    group             => 'gcsweb',
    role_name         => $role_name,
    role_description  => 'Globus identity mapping lookups',
    privileges        => [$role_name],
    custom_privileges => { $role_name => [$role_name] },
    permissions       => {
      $role_name => {
        'type'                => 'user',
        'ipapermright'        => ['read', 'search', 'compare'],
        'attrs'               => ['uid', 'ipaidpsub', 'nsaccountlock', 'objectclass'],
        'ipapermbindruletype' => 'permission',
      },
    },
    require           => Exec['globus-node-setup'],
  }
}
