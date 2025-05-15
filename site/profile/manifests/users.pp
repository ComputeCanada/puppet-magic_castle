class profile::users::ldap (
  Hash $users,
  Array[String] $access_tags,
) {
  Exec <| title == 'ipa-install' |> -> Profile::Users::Ldap_user <| |>
  Exec <| title == 'hbac_rules' |> ~> Profile::Users::Ldap_user <| |>
  Exec <| tag == profile::accounts |> -> Profile::Users::Ldap_user <| |>
  Service <| tag == profile::freeipa |> -> Profile::Users::Ldap_user <| |>
  Service <| tag == profile::accounts |> -> Profile::Users::Ldap_user <| |>

  file { '/sbin/ipa_create_user.py':
    source => 'puppet:///modules/profile/users/ipa_create_user.py',
    mode   => '0755',
  }

  ensure_resources(profile::users::ldap_user, $users, { 'access_tags' => $access_tags })
}

class profile::users::local (
  Hash $users
) {
  file { '/etc/sudoers.d/90-puppet-users':
    ensure => file,
    mode   => '0440',
    owner  => 'root',
    group  => 'root',
  }

  # file { '/etc/sudoers.d/90-cloud-init-users':
  #   ensure  => absent,
  #   require => $users.map | $k, $v | { Profile::Users::Local_user[$k] },
  # }

  ensure_resources(profile::users::local_user, $users)
}

define profile::users::ldap_user (
  Array[String] $groups,
  Array[String] $access_tags,
  Array[String] $public_keys = [],
  Integer[0] $count = 1,
  Boolean $manage_password = true,
  Optional[String[1]] $passwd = undef,
) {
  $admin_password = lookup('profile::freeipa::server::admin_password')
  $unique_group = "hbac-${name}"
  $posix_group = join($groups.map |$group| { "--posix_group ${group}" }, ' ')
  $nonposix_group = "--nonposix_group ${unique_group}"
  $sshpubkey_string = join($public_keys.map |$key| { "--sshpubkey '${key}'" }, ' ')
  $cmd_args = "${posix_group} ${nonposix_group} ${$sshpubkey_string}"
  if $count > 1 {
    $prefix = $name
    $command = "kinit_wrapper ipa_create_user.py $(seq -w ${count} | sed 's/^/${prefix}/') ${cmd_args}"
    $unless = "getent passwd $(seq -w ${count} | sed 's/^/${prefix}/')"
    $timeout = $count * 10
  } elsif $count == 1 {
    $command = "kinit_wrapper ipa_create_user.py ${name} ${cmd_args}"
    $unless = "getent passwd ${name}"
    $timeout = 10
  }

  if $passwd {
    $environment = ["IPA_ADMIN_PASSWD=${admin_password}", "IPA_USER_PASSWD=${passwd}"]
  } else {
    $environment = ["IPA_ADMIN_PASSWD=${admin_password}"]
  }

  if $count > 0 {
    exec { "ldap_user_${name}" :
      command     => $command,
      unless      => $unless,
      environment => $environment,
      path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
      timeout     => $timeout,
      require     => [
        File['kinit_wrapper'],
        File['/sbin/ipa_create_user.py'],
      ],
    }

    $access_tags.each |$tag| {
      exec { "ipa_hbacrule_${name}_${tag}":
        command     => "kinit_wrapper ipa hbacrule-add-user ${tag} --groups=${unique_group}",
        refreshonly => true,
        environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
        require     => [File['kinit_wrapper'],],
        path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
        returns     => [0, 1, 2],
        subscribe   => [
          Exec["ldap_user_${name}"],
        ],
      }
    }

    if $manage_password and $passwd {
      $ds_password = lookup('profile::freeipa::server::ds_password')
      $ipa_domain = lookup('profile::freeipa::base::ipa_domain')
      $fqdn = "${facts['networking']['hostname']}.${ipa_domain}"
      $ldap_dc_string = join(split($ipa_domain, '[.]').map |$dc| { "dc=${dc}" }, ',')

      $ldad_passwd_cmd = @("EOT")
        ldappasswd -ZZ -H ldap://${fqdn} \
        -x -D "cn=Directory Manager" -w "${ds_password}" \
        -S "uid={},cn=users,cn=accounts,${ldap_dc_string}" \
        -s "${passwd}"
        |EOT
      if $count > 1 {
        $reset_password_cmd = "seq -w ${count} | sed 's/^/${prefix}/' | xargs -I '{}' ${ldad_passwd_cmd}"
        $check_password_cmd = "echo ${passwd} | kinit $(seq -w ${count} | sed 's/^/${prefix}/' | head -n1) && kdestroy"
      } else {
        $reset_password_cmd = regsubst($ldad_passwd_cmd, '{}', $name)
        $check_password_cmd = "echo ${passwd} | kinit ${name} && kdestroy"
      }

      exec { "ldap_reset_password_${name}":
        command => Sensitive($reset_password_cmd),
        unless  => Sensitive($check_password_cmd),
        path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
      }
    }
  }
}

define profile::users::local_user (
  Array[String] $public_keys,
  Array[String] $groups,
  Boolean $sudoer = false,
  String $selinux_user = 'unconfined_u',
  String $mls_range = 's0-s0:c0.c1023',
  String $authenticationmethods = '',
  Boolean $manage_home = true,
  Boolean $purge_ssh_keys = true,
  Optional[String] $shell = undef,
  Optional[Integer] $uid = undef,
  Optional[Integer] $gid = undef,
  String $group = $name,
  String $home = "/${name}",
) {
  ensure_resource('group', $group, {
      ensure     => present,
      gid        => $gid,
      forcelocal => true,
    }
  )
  # Configure local account and ssh keys
  user { $name:
    ensure         => present,
    forcelocal     => true,
    uid            => $uid,
    gid            => $group,
    groups         => $groups,
    home           => $home,
    purge_ssh_keys => $purge_ssh_keys,
    managehome     => $manage_home,
    shell          => $shell,
    require        => Group[$group],
  }

  if $manage_home {
    selinux::exec_restorecon { $home:
      subscribe=> User[$name]
    }
  }

  $public_keys.each | Integer $index, String $sshkey | {
    $split = split($sshkey, ' ')
    $key_type_index = $split.index|$value| { $value =~ /^(?:ssh|ecdsa).*$/ }

    $key_type = $split[$key_type_index]
    $key_value = $split[$key_type_index+1]

    if $key_type_index != 0 {
      $key_options = ssh_split_options($split[0, $key_type_index].join(' '))
    } else {
      $key_options = undef
    }
    if length($split) > $key_type_index + 2 {
      $comment_index = $key_type_index + 2
      $comment = String($split[$comment_index, -1].join(' '), '%t')
      $key_name = "${name}_${index}:${comment}"
    } else {
      $key_name = "${name}_${index}"
    }
    ssh_authorized_key { "${name}_${index}":
      ensure  => present,
      name    => $key_name,
      user    => $name,
      type    => $key_type,
      key     => $key_value,
      options => $key_options,
    }
  }

  # Configure user selinux mapping
  exec { "selinux_login_${name}":
    command => "semanage login -a -S targeted -s '${selinux_user}' -r '${mls_range}' ${name}",
    unless  => "grep -q '${name}:${selinux_user}:${mls_range}' /etc/selinux/targeted/seusers",
    path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
  }

  $ensure_sudoer = $sudoer ? { true => 'present', false => 'absent' }
  file_line { "sudoer_${name}":
    ensure  => $ensure_sudoer,
    path    => '/etc/sudoers.d/90-puppet-users',
    line    => "${name} ALL=(ALL) NOPASSWD:ALL",
    require => File['/etc/sudoers.d/90-puppet-users'],
  }

  if $authenticationmethods != '' {
    sshd_config { "${name} authenticationmethods":
      ensure    => present,
      condition => "User ${name}",
      key       => 'AuthenticationMethods',
      value     => $authenticationmethods,
      target    => '/etc/ssh/sshd_config.d/50-authenticationmethods.conf',
      notify    => Service['sshd']
    }
  }
}
