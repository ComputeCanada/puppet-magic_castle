class profile::ssh::base {
  service { 'sshd':
    ensure => running,
    enable => true,
  }

  sshd_config { 'PermitRootLogin':
    ensure => present,
    value  => 'no',
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
  } elsif versioncmp($::facts['os']['release']['major'], '8') >= 1 {
    # In RedHat 9, the sshd policies are defined as an include that of the
    # crypto policies. Parameters defined before the include supersede
    # the crypto policy. The include is done in a file named 50-redhat.conf.
    file { '/etc/ssh/sshd_config.d/49-magic_castle.conf':
      source => 'puppet:///modules/profile/base/opensshserver-9.config',
      notify => Service['sshd'],
    }
  } elsif versioncmp($::facts['os']['release']['major'], '8') < 0 {
    file_line { 'MACs':
      ensure => present,
      path   => '/etc/ssh/sshd_config',
      line   => 'MACs umac-128-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com',
      notify => Service['sshd'],
    }

    file_line { 'KexAlgorithms':
      ensure => present,
      path   => '/etc/ssh/sshd_config',
      line   => 'KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org',
      notify => Service['sshd'],
    }

    file_line { 'HostKeyAlgorithms':
      ensure => present,
      path   => '/etc/ssh/sshd_config',
      line   => 'HostKeyAlgorithms ssh-rsa',
      notify => Service['sshd'],
    }

    file_line { 'Ciphers':
      ensure => present,
      path   => '/etc/ssh/sshd_config',
      line   => 'Ciphers chacha20-poly1305@openssh.com,aes128-ctr,aes192-ctr,aes256-ctr,aes128-gcm@openssh.com,aes256-gcm@openssh.com',
      notify => Service['sshd'],
    }
  }
}

# building /etc/ssh/ssh_known_hosts
# for host based authentication
class profile::ssh::known_hosts {
  $instances = lookup('terraform.instances')
  $domain_name = lookup('profile::freeipa::base::domain_name')
  $int_domain_name = "int.${domain_name}"

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
          'host_aliases' => ["${k}.${int_domain_name}", $v['local_ip'],],
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
