class profile::sssd::client(
  Hash $domains
){
  require profile::freeipa::client

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

  service { 'sssd':
    ensure => running,
    enable => true,
  }
}
