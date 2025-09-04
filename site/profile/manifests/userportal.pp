class profile::userportal {
  $instances = lookup('terraform.instances')
  $logins = keys($instances.filter |$keys, $values| { 'login' in $values['tags'] })

  $domain_name = lookup('profile::freeipa::base::domain_name')
  $int_domain_name = "int.${domain_name}"
  $base_dn = join(split($int_domain_name, '[.]').map |$dc| { "dc=${dc}" }, ',')

  class { 'trailblazing_turtle':
    root_api_token  => lookup('trailblazing_turtle::server::root_api_token'),
    password        => lookup('trailblazing_turtle::server::password'),
    prometheus_ip   => lookup('trailblazing_turtle::server::prometheus_ip'),
    prometheus_port => lookup('trailblazing_turtle::server::prometheus_port'),
    db_ip           => lookup('trailblazing_turtle::server::db_ip'),
    db_port         => lookup('trailblazing_turtle::server::db_port'),
    ldap_password   => lookup('trailblazing_turtle::server::ldap_password'),
    slurm_password  => lookup('trailblazing_turtle::server::slurm_password'),
    cluster_name    => lookup('trailblazing_turtle::server::cluster_name'),
    subdomain       => lookup('trailblazing_turtle::subdomain'),
    logins          => $logins,
    base_dn         => $base_dn,
    domain_name     => $domain_name,
  }
  Class['trailblazing_turtle'] ~> Service['httpd']
}
