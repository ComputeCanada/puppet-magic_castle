class profile::sssd::client(
  Hash $domains
){
  require profile::freeipa::client

  package { 'sssd-ldap': }

  $domain_name = lookup('profile::freeipa::base::domain_name')
  $ipa_domain = "int.${domain_name}"

  $domains.map | $key, $values | {
    file { "/etc/sssd/conf.d/${key}.conf":
      ensure  => 'present',
      owner   => 'root',
      group   => 'root',
      mode    => '0600',
      content =>  epp('profile/sssd/sssd.conf', {
        'ipa_domain' => $ipa_domain,
        'domains'    => $domains,
        'hostname'   => $::hostname,
      }),
      seltype => 'sssd_conf_t',
      notify  => Service['sssd']
    }

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
      break()
    }
  }

  $domain_list = join([$ipa_domain] + keys($domains), ',')
  file_line { '/etc/sssd/sssd.conf':
    ensure => present,
    path   => '/etc/sssd/sssd.conf',
    line   => "domains = ${domain_list}",
    match  => "^domains = ${$ipa_domain}$",
    notify => Service['sssd'],
  }

  service { 'sssd':
    ensure => running,
    enable => true,
  }
}
