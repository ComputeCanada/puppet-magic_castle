class profile::metrix {
  $instances = lookup('terraform.instances')
  $logins = keys($instances.filter |$keys, $values| { 'login' in $values['tags'] })

  $domain_name = lookup('terraform.data.domain_name')
  $int_domain_name = lookup('profile::freeipa::base::ipa_domain')
  $base_dn = join(split($int_domain_name, '[.]').map |$dc| { "dc=${dc}" }, ',')

  class { 'metrix':
    root_api_token  => lookup('metrix::root_api_token'),
    password        => lookup('metrix::password'),
    prometheus_ip   => lookup('metrix::prometheus_ip'),
    prometheus_port => lookup('metrix::prometheus_port'),
    db_ip           => lookup('metrix::db_ip'),
    db_port         => lookup('metrix::db_port'),
    ldap_password   => lookup('metrix::ldap_password'),
    slurm_password  => lookup('metrix::slurm_password'),
    cluster_name    => lookup('metrix::cluster_name'),
    subdomain       => lookup('metrix::subdomain'),
    logins          => $logins,
    base_dn         => $base_dn,
    domain_name     => $domain_name,
  }
  Class['metrix'] ~> Service['httpd']
}
