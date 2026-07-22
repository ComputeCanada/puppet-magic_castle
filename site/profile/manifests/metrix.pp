class profile::metrix (
  Array[String] $login_tags = ['login']
) {
  include mysql::server
  stdlib::ensure_packages(['httpd'], { ensure => 'installed' })

  if versioncmp($facts['os']['release']['major'], '9') == 0 {
    package { 'mariadb':
      ensure      => '10.11',
      provider    => 'dnfmodule',
      enable_only => true,
      before      => Package['mysql-server'],
    }
  }

  $instances = lookup('terraform.instances')
  $logins = keys($instances.filter |$keys, $values| { !intersection($login_tags, $values['tags']).empty })

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
    slurm_user      => lookup('metrix::slurm_user'),
    slurm_password  => lookup('metrix::slurm_password'),
    slurm_db_ip     => lookup('metrix::slurm_db_ip'),
    slurm_db_port   => lookup('metrix::slurm_db_port'),
    cluster_name    => lookup('metrix::cluster_name'),
    subdomain       => lookup('metrix::subdomain'),
    logins          => $logins,
    base_dn         => $base_dn,
    domain_name     => $domain_name,
  }

  ensure_resource('service', 'httpd', { 'ensure' => running, 'enable' => true, 'restart' => '/usr/bin/systemctl reload httpd' })
  Class['metrix'] ~> Service['httpd']
}
