class profile::users::ldap (
  Hash $users,
  Hash $groups,
) {
  Exec <| title == 'ipa-install' |> -> Profile::Users::Ldap_group <| |>
  Service <| |> ->  Profile::Users::Ldap_group <| |>
  Profile::Users::Ldap_group <| |> -> Profile::Users::Ldap_user <| |>

  file { '/sbin/ipa_create_user.py':
    source => 'puppet:///modules/profile/users/ipa_create_user.py',
    mode   => '0755',
  }

  # After adding a user or a group, we need to invalidate the SSS cache
  # that could otherwise return that the user or the group does not exist
  # when probing the Unix user account and password database or
  # the Unix group database. The command is only executed when a user or
  # a group has been created during a Puppet run.
  exec { 'sss_cache -E':
    refreshonly => true,
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
  }

  $users_groups = Hash(unique(flatten($users.map |$key, $values| { pick($values['groups'], []) })).map|$group_name| { [$group_name, {}] })
  ensure_resources(profile::users::ldap_group, $users_groups + $groups)
  ensure_resources(profile::users::ldap_user, $users)
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

define profile::users::ldap_group (
  Boolean $posix = true,
  Boolean $automember = false,
  Optional[Array[String]] $hbac_rules = undef,
  Optional[Integer[1]] $gid = undef,
) {
  if !$posix and $gid != undef {
    fail('gid cannot be used with a non-POSIX group')
  }
  if $gid != undef {
    profile::validate_ldap_id($gid, "LDAP group ${name} gid")
  }

  if $posix {
    $arg = $gid ? {
      undef   => '',
      default => "--gid=${gid}",
    }
  }
  else {
    $arg = '--nonposix'
  }
  profile::freeipa::admin_exec { "ldap_group_${name}":
    command => "ipa group-add ${name} ${arg}",
    unless  => "getent group ${name}",
    notify  => Exec['sss_cache -E'],
    require => [
      Exec['ipa-install'],
    ],
  }

  if $hbac_rules != undef or $automember {
    file { "/etc/ipa/group_rules_${name}.py":
      mode    => '0700',
      content => epp(
        'profile/freeipa/group_rules.py',
        {
          'group'      => $name,
          'automember' => $automember,
          'hbac_rules' => $hbac_rules,
        }
      ),
    }
    profile::freeipa::admin_exec { "group_rules_${name}":
      command     => "ipa console /etc/ipa/group_rules_${name}.py",
      refreshonly => true,
      subscribe   => [
        File["/etc/ipa/group_rules_${name}.py"],
        Profile::Freeipa::Admin_exec['hbac_rules'],
        Profile::Freeipa::Admin_exec["ldap_group_${name}"],
      ],
    }
  }
}

define profile::users::ldap_user (
  Array[String] $groups = [],
  Array[String] $public_keys = [],
  Integer[0] $count = 1,
  Boolean $manage_password = true,
  Optional[String[1]] $passwd = undef,
  Optional[String[1]] $idp_user_id = undef,
  Optional[Integer[1]] $uid = undef,
  Optional[Integer[1]] $gid = undef,
) {
  if $idp_user_id != undef and $count > 1 {
    fail('idp_user_id cannot be used with count > 1')
  }
  if $count > 0 {
    if $uid != undef {
      profile::validate_ldap_id($uid, "LDAP user ${name} uid", $count)
    }
    if $gid != undef {
      profile::validate_ldap_id($gid, "LDAP user ${name} gid", $count)
    }
  }

  $group_args = join($groups.map |$group| { "--group ${group}" }, ' ')
  $sshpubkey_string = join($public_keys.map |$key| { "--sshpubkey '${key}'" }, ' ')
  $idp_args = $idp_user_id ? {
    undef   => '',
    default => shellquote("--idp-user-id=${idp_user_id}"),
  }
  $cmd_args = "${group_args} ${$sshpubkey_string} ${idp_args}"
  if $count > 1 {
    $page_size = 50
    $prefix = $name
    $exec_name = range(1, $count, $page_size).map |$i| {
      "ldap_user_${name}_${i}-${min($i + $page_size - 1, $count)}"
    }
    $command = range(1, $count, $page_size).map |$i| {
      $uid_arg = $uid ? {
        undef   => '',
        default => "--uid=${uid + $i - 1}",
      }
      $gid_arg = $gid ? {
        undef   => '',
        default => "--gid=${gid + $i - 1}",
      }
      "ipa_create_user.py $(seq -f'${prefix}%0${length(String($count))}g' ${i} ${min($count, $i + $page_size - 1)}) ${cmd_args} ${uid_arg} ${gid_arg}"
    }
    $timeout = $page_size * 10
  } elsif $count == 1 {
    $exec_name = ["ldap_user_${name}"]
    $uid_arg = $uid ? {
      undef   => '',
      default => "--uid=${uid}",
    }
    $gid_arg = $gid ? {
      undef   => '',
      default => "--gid=${gid}",
    }
    $command = ["ipa_create_user.py ${name} ${cmd_args} ${uid_arg} ${gid_arg}"]
    $timeout = 10
  }

  if $count > 0 {
    $exec_name.each |Integer $i, String $exec_name_i| {
      profile::freeipa::admin_exec { $exec_name_i:
        command => $command[$i],
        unless  => "${command[$i]} --dry",
        timeout => $timeout,
        require => [
          File['/sbin/ipa_create_user.py'],
        ],
        notify  => Exec['sss_cache -E'],
      }
    }

    if $passwd {
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
        $set_password_cmd = range(1, $count, $page_size).map |$i| {
          "seq -f'${prefix}%0${length(String($count))}g' ${i} ${min($count, $i + $page_size - 1)} | xargs -I '{}' ${ldad_passwd_cmd}"
        }
        $check_password_cmd = range(1, $count, $page_size).map |$i| {
          "echo ${passwd} | kinit $(seq -f'${prefix}%0${length(String($count))}g' ${i} ${min($count, $i + $page_size - 1)} | shuf | head -n1) && kdestroy"
        }
      } else {
        $set_password_cmd = [regsubst($ldad_passwd_cmd, '{}', $name)]
        $check_password_cmd = ["echo ${passwd} | kinit ${name} && kdestroy"]
      }

      $exec_name.each |Integer $i, String $exec_name_i| {
        exec { "ldap_set_password_${$exec_name_i}":
          command     => Sensitive($set_password_cmd[$i]),
          unless      => Sensitive($check_password_cmd[$i]),
          path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
          refreshonly => ! $manage_password,
          subscribe   => Profile::Freeipa::Admin_exec[$exec_name_i],
        }
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
      subscribe => User[$name]
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

  # Configure selinux user login mapping
  selinux::login { $name:
    ensure             => 'present',
    selinux_login_name => $name,
    selinux_user       => $selinux_user,
    selinux_mlsrange   => $mls_range,
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
      notify    => Service['sshd'],
      require   => File['/etc/ssh/sshd_config.d'],
    }
  }
}
