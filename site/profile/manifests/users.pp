class profile::users::ldap(
  Hash $users
) {
  require profile::accounts

  file { '/sbin/ipa_create_user.py':
    source => 'puppet:///modules/profile/users/ipa_create_user.py',
    mode   => '0755'
  }

  ensure_resources(profile::users::ldap_user, $users)
}

class profile::users::local (
  Hash $users
)
{
  file { '/etc/sudoers.d/90-puppet-users':
    ensure => present,
    mode   => '0440',
    owner  => 'root',
    group  => 'root',
  }

  file { '/etc/sudoers.d/90-cloud-init-users':
    ensure => absent,
  }

  ensure_resources(profile::users::local_user, $users)
}

define profile::users::ldap_user (
  String[8] $passwd,
  Array[String] $groups,
  Integer[0] $count = 1,
  )
{
  $admin_passwd = lookup('profile::freeipa::base::admin_passwd')
  $group_string = join($groups.map |$group| { "--group ${group}" }, ' ')
  if $count > 1 {
    $prefix = $name
    $command = "kinit_wrapper ipa_create_user.py $(seq -w ${count} | sed 's/^/${prefix}/') ${group_string}"
    $unless = "getent passwd $(seq -w ${count} | sed 's/^/${prefix}/')"
    $timeout = $count * 10
  } elsif $count == 1 {
    $command = "kinit_wrapper ipa_create_user.py ${name} ${group_string}"
    $timeout = 5
  }

  if $count > 0 {
    exec{ "ldap_user_${name}":
      command     => $command,
      unless      => $unless,
      environment => ["IPA_ADMIN_PASSWD=${admin_passwd}",
                      "IPA_USER_PASSWD=${passwd}"],
      path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
      timeout     => $timeout,
    }
  }

}

define profile::users::local_user (
  Array[String] $public_keys,
  Array[String] $groups,
  Boolean $sudoer = false,
  String $selinux_user = 'unconfined_u',
  String $mls_range = 's0-s0:c0.c1023',
) {

  # Configure local account and ssh keys
  user { $name:
    ensure         => present,
    groups         => $groups,
    home           => "/${name}",
    purge_ssh_keys => true,
    managehome     => true,
    notify         => Selinux::Exec_restorecon["/${name}"]
  }

  selinux::exec_restorecon { "/${name}": }

  $public_keys.each | Integer $index, String $sshkey | {
    $split = split($sshkey, ' ')
    if length($split) > 2 {
      $keyname = String($split[2], '%t')
    } else {
      $keyname = "sshkey_${index}"
    }
    ssh_authorized_key { "${name}_${keyname}":
      ensure => present,
      user   => $name,
      type   => $split[0],
      key    => $split[1],
    }
  }

  # Configure user selinux mapping
  exec { "selinux_login_${name}":
    command => "semanage login -a -S targeted -s '${selinux_user}' -r '${mls_range}' ${name}",
    unless  => "grep -q '${name}:${selinux_user}:${mls_range}' /etc/selinux/targeted/seusers",
    path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
  }

  $ensure_sudoer = $sudoer ? { true => present, false => absent }
  file_line { "sudoer_${name}":
      ensure  => $ensure_sudoer,
      path    => '/etc/sudoers.d/90-puppet-users',
      line    => "${name} ALL=(ALL) NOPASSWD:ALL",
      require => File['/etc/sudoers.d/90-puppet-users']
  }
}
