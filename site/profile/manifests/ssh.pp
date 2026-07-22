class profile::ssh::base (
  Boolean $disable_passwd_auth = false,
) {
  $password_auth = $disable_passwd_auth ? { true => 'no', false => 'yes' }
  $ciphers = [
    'chacha20-poly1305@openssh.com',
    'aes256-gcm@openssh.com',
    'aes128-gcm@openssh.com',
    'aes256-ctr',
    'aes192-ctr',
    'aes128-ctr',
  ]
  $macs = [
    'hmac-sha2-256-etm@openssh.com',
    'hmac-sha2-512-etm@openssh.com',
    'umac-128-etm@openssh.com',
  ]
  $gssapikexalgorithms = ['gss-curve25519-sha256-']
  $kexalgorithms_prequantum = [
    'curve25519-sha256',
    'curve25519-sha256@libssh.org',
    'diffie-hellman-group16-sha512',
    'diffie-hellman-group18-sha512',
    'diffie-hellman-group-exchange-sha256',
  ]
  $kexlagorithms_postquantum = [
    'mlkem768x25519-sha256',
    'sntrup761x25519-sha512',
  ]
  $kexalgorithms = (
    $kexalgorithms_prequantum + (
      versioncmp(pick($facts['openssh_server_version'], '8.7'), '9.9') >= 0 ? { true => $kexlagorithms_postquantum, false => [] }
    )
  )
  $hostkeyalgorithms = [
    'ssh-ed25519',
    'ssh-ed25519-cert-v01@openssh.com',
    'rsa-sha2-256',
    'rsa-sha2-512',
  ]
  $pubkeyacceptedkeytypes = [
    'ssh-ed25519',
    'ssh-ed25519-cert-v01@openssh.com',
    'rsa-sha2-256',
    'rsa-sha2-512',
  ]

  service { 'sshd':
    ensure => running,
    enable => true,
  }

  file { '/etc/ssh/sshd_config.d':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0700',
  }

  file { '/etc/ssh/sshd_config.d/01-puppet.conf':
    ensure  => file,
    content => epp('profile/ssh/01-puppet.conf',
      {
        'password_auth'          => $password_auth,
        'ciphers'                => $ciphers,
        'macs'                   => $macs,
        'gssapikexalgorithms'    => $gssapikexalgorithms,
        'kexalgorithms'          => $kexalgorithms,
        'hostkeyalgorithms'      => $hostkeyalgorithms,
        'pubkeyacceptedkeytypes' => $pubkeyacceptedkeytypes,
      },
    ),
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    require => File['/etc/ssh/sshd_config.d'],
    notify  => Service['sshd'],
  }

  file { '/etc/ssh/sshd_config.d/50-authenticationmethods.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    require => File['/etc/ssh/sshd_config.d'],
  }

  file { '/etc/ssh/sshd_config.d/50-cloud-init.conf':
    ensure => absent,
    notify => Service['sshd'],
  }

  sshd_config { 'Include':
    ensure => present,
    value  => '/etc/ssh/sshd_config.d/*',
    notify => Service['sshd'],
  }

  sshd_config { 'PermitRootLogin-sshd_config':
    ensure => absent,
    key    => 'PermitRootLogin',
    notify => Service['sshd'],
  }

  sshd_config { 'PasswordAuthentication-sshd_config':
    ensure => absent,
    key    => 'PasswordAuthentication',
    notify => Service['sshd'],
  }

  file { '/etc/ssh/ssh_host_ed25519_key':
    mode  => '0600',
    owner => 'root',
    group => 'root',
  }

  file { '/etc/ssh/ssh_host_ed25519_key.pub':
    mode  => '0644',
    owner => 'root',
    group => 'root',
  }

  file { '/etc/ssh/ssh_host_rsa_key':
    mode  => '0600',
    owner => 'root',
    group => 'root',
  }

  file { '/etc/ssh/ssh_host_rsa_key.pub':
    mode  => '0644',
    owner => 'root',
    group => 'root',
  }

  sshd_config { 'tf_sshd_AuthenticationMethods':
    ensure    => present,
    condition => 'User tf',
    key       => 'AuthenticationMethods',
    value     => 'publickey',
    target    => '/etc/ssh/sshd_config.d/50-authenticationmethods.conf',
    notify    => Service['sshd'],
    require   => File['/etc/ssh/sshd_config.d/50-authenticationmethods.conf'],
  }

  sshd_config { 'tf_sshd_AuthorizedKeysFile':
    ensure    => present,
    condition => 'User tf',
    key       => 'AuthorizedKeysFile',
    value     => '/etc/ssh/authorized_keys.%u',
    target    => '/etc/ssh/sshd_config.d/50-authenticationmethods.conf',
    notify    => Service['sshd'],
    require   => File['/etc/ssh/sshd_config.d/50-authenticationmethods.conf'],
  }

  $tf_public_key = lookup('terraform.data.tf_public_key', undef, undef, undef)
  $bastion_tags  = lookup('terraform.data.bastion_tags', undef, undef, [])
  $tags          = lookup('terraform.self.tags')
  $puppetserver_ips = lookup('terraform.tag_ip.puppet', undef, undef, undef)

  if $puppetserver_ips {
    if 'puppet' in $tags {
      $tf_authorized_keys_options = 'pty'
    } elsif ! intersection($tags, $bastion_tags).empty {
      $permitopen = $puppetserver_ips.map |$ip| { "permitopen=\"${ip}:22\"" }.join(',')
      $tf_authorized_keys_options = "${permitopen},port-forwarding,command=\"/sbin/nologin\""
    } else {
      $tf_authorized_keys_options = undef
    }
  } else {
    $tf_authorized_keys_options = undef
  }

  if $tf_authorized_keys_options and $tf_public_key {
    $tf_authorized_keys = "restrict,${tf_authorized_keys_options} ${tf_public_key}"
    file { '/etc/ssh/authorized_keys.tf':
      content => $tf_authorized_keys,
      mode    => '0644',
      owner   => 'root',
      group   => 'root',
    }
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

  if versioncmp($::facts['os']['release']['major'], '10') == 0 {
    ensure_packages(['openssh-keysign'], { ensure => 'present' })
  }

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
