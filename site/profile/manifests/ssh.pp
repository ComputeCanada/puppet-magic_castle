# @summary Enable SSH hostbased authentication on the instance including this class
# @param shosts_tags Tags of instances that can connect this server using hostbased authentication
class profile::ssh::hostbased_auth::server (
  Array[String] $shosts_tags = ['login', 'node']
) {
  $instances = lookup('terraform.instances')
  $domain_name = lookup('profile::freeipa::base::domain_name')
  $hosts = $instances.filter |$k, $v| { ! intersection($v['tags'], $shosts_tags).empty }
  $shosts = join($hosts.map |$k, $v| { "${k}.int.${domain_name}" }, "\n")

  file { '/etc/ssh/shosts.equiv':
    content => $shosts,
  }

  file_line { 'HostbasedAuthentication':
    ensure => present,
    path   => '/etc/ssh/sshd_config',
    line   => 'HostbasedAuthentication yes',
    notify => Service['sshd'],
  }

  file_line { 'UseDNS':
    ensure => present,
    path   => '/etc/ssh/sshd_config',
    line   => 'UseDNS yes',
    notify => Service['sshd'],
  }

  selinux::boolean { 'ssh_keysign': }
}

class profile::ssh::hostbased_auth::client {
  ssh_config { 'EnableSSHKeysign':
    ensure => present,
    host   => '*',
    value  => 'yes',
  }

  ssh_config { 'HostbasedAuthentication':
    ensure => present,
    host   => '*',
    value  => 'yes',
  }
}
