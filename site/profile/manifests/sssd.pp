class profile::sssd::client(
  Hash[String, Any] $domains = {},
  Array[String] $access_tags = ['login', 'node'],
  Optional[Boolean] $deny_access = undef,
){
  ensure_resource('service', 'sssd', { 'ensure' => running, 'enable' => true })

  package { 'sssd-ldap': }

  if ! defined('$deny_access') {
    $tags = lookup('terraform.self.tags')
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
  |EOT
      file {'/etc/openldap/ldap.conf':
        content => $ldap_conf_template,
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
      }
    }
    break()
  }

  if $facts['ipa']['installed'] {
    $domain_list = join([$facts['ipa']['domain']] + keys($domains), ',')
  } else {
    $domain_list = join(keys($domains), ',')
  }

  if ! $domain_list.empty {
    $augeas_domains = "set target[ . = 'sssd']/domains ${domain_list}"
  } else {
    $augeas_domains = ''
  }

  file { '/etc/sssd/sssd.conf':
    ensure => 'file',
    owner  => 'root',
    group  => 'root',
    mode   => '0600',
    notify => Service['sssd'],
  }

  augeas { 'sssd.conf':
    lens    => 'sssd.lns',
    incl    => '/etc/sssd/sssd.conf',
    changes => [
      "set target[ . = 'sssd'] 'sssd'",
      "set target[ . = 'sssd']/services 'nss, sudo, pam, ssh'",
      $augeas_domains,
    ],
    require => File['/etc/sssd/sssd.conf'],
    notify  => Service['sssd'],
  }
}
