class profile::userportal {
  $instances = lookup('terraform.instances')
  $logins = $instances.filter |$keys, $values| { 'login' in $values['tags'] }

  $domain_name = lookup('profile::freeipa::base::domain_name')
  $int_domain_name = "int.${domain_name}"
  $base_dn = join(split($int_domain_name, '[.]').map |$dc| { "dc=${dc}" }, ',')
  $admin_password = lookup('profile::freeipa::server::admin_password')

  class { 'trailblazing_turtle':
    logins      => $logins,
    base_dn     => $base_dn,
    domain_name => $domain_name,
  }
}
