class profile::accounts (
  String $project_regex
) {
  require profile::freeipa::server
  require profile::freeipa::mokey
  require profile::nfs::server
  require profile::slurm::accounting

  file { '/sbin/ipa_create_user.py':
    source => 'puppet:///modules/profile/accounts/ipa_create_user.py',
    mode   => '0755'
  }

  $nfs_devices = lookup('profile::nfs::server::devices', undef, undef, {})
  $with_home = 'home' in $nfs_devices
  $with_project = 'project' in $nfs_devices
  $with_scratch = 'scratch' in $nfs_devices

  file { '/sbin/mkhome.sh':
    ensure  => 'present',
    content => epp('profile/accounts/mkhome.sh', {
      with_home    => $with_home,
      with_scratch => $with_scratch,
    }),
    mode    => '0755',
    owner   => 'root',
  }

  file { 'mkhome.service':
    ensure => 'present',
    path   => '/lib/systemd/system/mkhome.service',
    source => 'puppet:///modules/profile/accounts/mkhome.service'
  }

  if $with_home or $with_scratch {
    service { 'mkhome':
      ensure    => running,
      enable    => true,
      subscribe => [
        File['/sbin/mkhome.sh'],
        File['mkhome.service'],
      ]
    }
  }

  file { 'mkproject.service':
    ensure => 'present',
    path   => '/lib/systemd/system/mkproject.service',
    source => 'puppet:///modules/profile/accounts/mkproject.service'
  }

  file { '/sbin/mkproject.sh':
    ensure  => 'present',
    content => epp('profile/accounts/mkproject.sh', {
      project_regex => $project_regex,
      with_folder   => $with_project,
    }),
    mode    => '0755',
    owner   => 'root',
  }

  service { 'mkproject':
    ensure    => running,
    enable    => true,
    subscribe => [
      File['/sbin/mkproject.sh'],
      File['mkproject.service'],
    ]
  }
}

class profile::accounts::guests(
  String[8] $passwd,
  Integer[0] $nb_accounts,
  String[1] $prefix,
  Array[String] $groups,
  )
{
  require profile::accounts

  $admin_passwd = lookup('profile::freeipa::base::admin_passwd')
  if $nb_accounts > 0 {
    $group_string = join($groups.map |$group| { "--group ${group}" }, ' ')
    exec{ 'ipa_add_user':
      command     => "kinit_wrapper ipa_create_user.py $(seq -w ${nb_accounts} | sed 's/^/${prefix}/') ${group_string}",
      unless      => "getent passwd $(seq -w ${nb_accounts} | sed 's/^/${prefix}/')",
      environment => ["IPA_ADMIN_PASSWD=${admin_passwd}",
                      "IPA_USER_PASSWD=${passwd}"],
      path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
      timeout     => $nb_accounts * 10,
    }
  }
}

class profile::accounts::local (
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

  ensure_resources(profile::accounts::local_user, $users)
}

define profile::accounts::local_user (
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
