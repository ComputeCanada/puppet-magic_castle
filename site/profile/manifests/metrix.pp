class profile::metrix {
  include mysql::server

  package { 'mariadb':
    ensure      => '10.11',
    provider    => 'dnfmodule',
    enable_only => true,
    before      => Package['mysql-server'],
  }

  $instances = lookup('terraform.instances')
  $logins = keys($instances.filter |$keys, $values| { 'login' in $values['tags'] })

  $domain_name = lookup('terraform.data.domain_name')
  $int_domain_name = lookup('profile::freeipa::base::ipa_domain')
  $base_dn = join(split($int_domain_name, '[.]').map |$dc| { "dc=${dc}" }, ',')

  if lookup('terraform.tag_ip.metrix.0') != lookup('terraform.tag_ip.mgmt.0') {
    $slurm_db_ip = lookup('terraform.tag_ip.mgmt.0')
  }
  else {
    $slurm_db_ip = '127.0.0.1'
  }
  class { 'metrix':
    root_api_token  => lookup('metrix::root_api_token'),
    password        => lookup('metrix::password'),
    prometheus_ip   => lookup('metrix::prometheus_ip'),
    prometheus_port => lookup('metrix::prometheus_port'),
    db_ip           => lookup('metrix::db_ip'),
    db_port         => lookup('metrix::db_port'),
    ldap_password   => lookup('metrix::ldap_password'),
    slurm_user      => lookup('metrix::slurm_user'),
    slurm_password  => lookup('metrix::slurm_password'),
    slurm_db_ip     => $slurm_db_ip,
    slurm_db_port   => lookup('metrix::slurm_db_port'),
    cluster_name    => lookup('metrix::cluster_name'),
    subdomain       => lookup('metrix::subdomain'),
    logins          => $logins,
    base_dn         => $base_dn,
    domain_name     => $domain_name,
    auth_type       => lookup('metrix::auth_type')
  }
  Class['metrix'] ~> Service['httpd']
}
