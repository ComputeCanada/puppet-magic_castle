class profile::sssd::client(
  Hash $domains,
  Boolean $deny_access = false,
){
  package { 'sssd-ldap': }

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
        'config' => $config + extra_config,
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

  $domain_list = join([$ipa_domain] + keys($domains), ',')
  file_line { '/etc/sssd/sssd.conf':
    ensure  => present,
    path    => '/etc/sssd/sssd.conf',
    line    => "domains = ${domain_list}",
    match   => "^domains = ${$ipa_domain}$",
    notify  => Service['sssd'],
    require => Exec['ipa-install'],
  }

  service { 'sssd':
    ensure => running,
    enable => true,
  }
}
