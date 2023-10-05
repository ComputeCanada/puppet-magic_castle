class profile::sssd::client(
  Hash $domains = {},
  Array[String] $access_tags = ['login', 'node'],
  Optional[Boolean] $deny_access = undef,
){
  ensure_resource('service', 'sssd', { 'ensure' => running, 'enable' => true })

  package { 'sssd-ldap': }

  if ! defined('$deny_access') {
    $tags = lookup("terraform.instances.${facts['networking']['hostname']}.tags")
    $deny_access = intersection($tags, $access_tags).empty
  }

  if $deny_access {
    $extra_config = {
      'access_provider' => 'deny'
    }
  } else {
    $extra_config = {}
  }

  $domains.map | $domain, $config | {
    file { "/etc/sssd/conf.d/${domain}.conf":
      ensure  => 'present',
      owner   => 'root',
      group   => 'root',
      mode    => '0600',
      content =>  epp('profile/sssd/sssd.conf', {
        'domain' => $domain,
        'config' => $config + $extra_config,
      }),
      seltype => 'sssd_conf_t',
      notify  => Service['sssd']
    }
  }

  $domains.map | $key, $values | {
    if('ldap_tls_reqcert' in $values and $values['ldap_tls_reqcert'] in ['demand', 'hard']){
      $uris = join($values['ldap_uri'], ' ')
      $ldap_conf_template =  @("EOT")
# Managed by puppet
SASL_NOCANON    on
URI ${uris}
BASE ${values['ldap_search_base']}
EOT
      file {'/etc/openldap/ldap.conf':
        content => $ldap_conf_template,
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
      }
    }
    break()
  }

  $domain_name = lookup('profile::freeipa::base::domain_name')
  $ipa_domain = "int.${domain_name}"
  $domain_list = join([$ipa_domain] + keys($domains), ',')
  file_line { 'sssd_domains':
    ensure  => present,
    path    => '/etc/sssd/sssd.conf',
    line    => "domains = ${domain_list}",
    match   => "^domains = ${$ipa_domain}$",
    notify  => Service['sssd'],
    require => Exec['ipa-install'],
  }
}
