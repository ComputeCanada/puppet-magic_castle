class profile::ssh::base (
  Boolean $disable_passwd_auth = false,
) {
  service { 'sshd':
    ensure => running,
    enable => true,
  }

  sshd_config { 'Include':
    ensure => present,
    value  => '/etc/ssh/sshd_config.d/*',
    notify => Service['sshd'],
  }

  sshd_config { 'PermitRootLogin':
    ensure => present,
    value  => 'no',
    notify => Service['sshd'],
  }

  $password_auth = $disable_passwd_auth ? { true => 'no', false => 'yes' }
  sshd_config { 'PasswordAuthentication':
    ensure => present,
    value  => $password_auth,
    notify => Service['sshd'],
  }

  file { '/etc/ssh/ssh_host_ed25519_key':
    mode  => '0640',
    owner => 'root',
    group => 'ssh_keys',
  }

  file { '/etc/ssh/ssh_host_ed25519_key.pub':
    mode  => '0644',
    owner => 'root',
    group => 'ssh_keys',
  }

  file { '/etc/ssh/ssh_host_rsa_key':
    mode  => '0640',
    owner => 'root',
    group => 'ssh_keys',
  }

  file { '/etc/ssh/ssh_host_rsa_key.pub':
    mode  => '0644',
    owner => 'root',
    group => 'ssh_keys',
  }

  if versioncmp($::facts['os']['release']['major'], '8') == 0 {
    # sshd hardening in RedHat 8 requires fidgetting with crypto-policies
    # instead of modifying /etc/ssh/sshd_config
    # https://sshaudit.com/hardening_guides.html#rhel8
    # We replace the file in /usr/share/crypto-policies instead of
    # /etc/crypto-policies as suggested by sshaudit.com, because the script
    # update-crypto-policies can be called by RPM scripts and overwrites the
    # config in /etc by what's in /usr/share. The files in /etc/crypto-policies
    # are in just symlinks to /usr/share
    file { '/usr/share/crypto-policies/DEFAULT/opensshserver.txt':
      source => 'puppet:///modules/profile/base/opensshserver.config',
      notify => Service['sshd'],
    }
  } elsif versioncmp($::facts['os']['release']['major'], '9') >= 0 {
    # In RedHat 9, the sshd policies are defined as an include of the
    # crypto policies. Parameters defined before the include supersede
    # the crypto policy. The include is done in a file named 50-redhat.conf.
    file { '/etc/ssh/sshd_config.d/49-magic_castle.conf':
      mode   => '0700',
      owner  => 'root',
      group  => 'root',
      source => 'puppet:///modules/profile/base/opensshserver-9.config',
      notify => Service['sshd'],
    }
  }

  sshd_config { 'tf_sshd_AuthenticationMethods':
    ensure    => present,
    condition => 'User tf',
    key       => 'AuthenticationMethods',
    value     => 'publickey',
    target    => '/etc/ssh/sshd_config.d/50-authenticationmethods.conf',
    notify    => Service['sshd'],
  }

  sshd_config { 'tf_sshd_AuthorizedKeysFile':
    ensure    => present,
    condition => 'User tf',
    key       => 'AuthorizedKeysFile',
    value     => '/etc/ssh/authorized_keys.%u',
    target    => '/etc/ssh/sshd_config.d/50-authenticationmethods.conf',
    notify    => Service['sshd'],
  }

  $tf_public_key = lookup('terraform.data.tf_public_key')
  $tags          = lookup('terraform.self.tags')
  $puppetserver_ips = lookup('terraform.tag_ip.puppet')

  if 'puppet' in $tags {
    $tf_authorized_keys_options = 'pty'
  } else {
    $permitopen = $puppetserver_ips.map |$ip| { "permitopen=\"${ip}:22\"" }.join(',')
    $tf_authorized_keys_options = "${permitopen},port-forwarding,command=\"/sbin/nologin\""
  }

  $tf_authorized_keys = "restrict,${tf_authorized_keys_options} ${tf_public_key}"
  file { '/etc/ssh/authorized_keys.tf':
    content => $tf_authorized_keys,
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
  }
}

# building /etc/ssh/ssh_known_hosts
# for host based authentication
class profile::ssh::known_hosts {
  $instances = lookup('terraform.instances')
  $ipa_domain = lookup('profile::freeipa::base::ipa_domain')

  file { '/etc/ssh/ssh_known_hosts':
    content => '# This file is managed by Puppet',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    replace => false,
  }

  $type = 'ed25519'
  $sshkey_to_add = Hash(
    $instances.map |$k, $v| {
      [
        $k,
        {
          'key' => split($v['hostkeys'][$type], /\s/)[1],
          'type' => "ssh-${type}",
          'host_aliases' => ["${k}.${ipa_domain}"] + ( $v['local_ip'] != '' ? { true => [$v['local_ip']], false => [] }),
          'require' => File['/etc/ssh/ssh_known_hosts'],
        }
      ]
  })
  ensure_resources('sshkey', $sshkey_to_add)
}

# @summary Enable SSH hostbased authentication on the instance including this class
# @param shosts_tags Tags of instances that can connect this server using hostbased authentication
class profile::ssh::hostbased_auth::server (
  Array[String] $shosts_tags = ['login', 'node']
) {
  include profile::ssh::known_hosts

  $instances = lookup('terraform.instances')
  $ipa_domain = lookup('profile::freeipa::base::ipa_domain')
  $hosts = $instances.filter |$k, $v| { ! intersection($v['tags'], $shosts_tags).empty }
  $shosts = join($hosts.map |$k, $v| { "${k}.${ipa_domain}" }, "\n")

  file { '/etc/ssh/shosts.equiv':
    content => $shosts,
  }

  sshd_config { 'HostbasedAuthentication':
    ensure => present,
    value  => 'yes',
    notify => Service['sshd'],
  }

  sshd_config { 'UseDNS':
    ensure => present,
    value  => 'yes',
    notify => Service['sshd'],
  }

  selinux::boolean { 'ssh_keysign': }
}

class profile::ssh::hostbased_auth::client {
  include profile::ssh::known_hosts

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
