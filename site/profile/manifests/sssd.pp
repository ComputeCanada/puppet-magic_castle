class profile::sssd::client(
  Hash $domains
){
  require profile::freeipa::client

  package { 'sssd-ldap': }

  $domain_name = lookup('profile::freeipa::base::domain_name')
  $ipa_domain = "int.${domain_name}"

  file { '/etc/sssd/sssd.conf':
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
      break()
    }
  }

  service { 'sssd':
    ensure => running,
    enable => true,
  }
}
