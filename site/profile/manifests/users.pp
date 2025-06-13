class profile::users::ldap (
  Hash $users,
  Hash $groups,
) {
  Exec <| title == 'ipa-install' |> -> Profile::Users::Ldap_group <| |>
  Exec <| title == 'hbac_rules' |> ~> Profile::Users::Ldap_group <| |>
  Exec <| tag == profile::accounts |> ->  Profile::Users::Ldap_group <| |>
  Service <| |> ->  Profile::Users::Ldap_group <| |>
  Profile::Users::Ldap_group <| |> -> Profile::Users::Ldap_user <| |>

  file { '/sbin/ipa_create_user.py':
    source => 'puppet:///modules/profile/users/ipa_create_user.py',
    mode   => '0755',
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
  Optional[Array[String]] $hbacrules = undef,
) {
  $admin_password = lookup('profile::freeipa::server::admin_password')
  $environment = ["IPA_ADMIN_PASSWD=${admin_password}"]
  if $posix {
    $arg = ''
  }
  else {
    $arg = '--nonposix'
  }
  exec { "ldap_group_${name}":
    command     => "kinit_wrapper ipa group-add ${name} ${arg}",
    environment => $environment,
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    unless      => "kinit_wrapper ipa group-show ${name}",
    require     => [
      Exec['ipa-install'],
      File['kinit_wrapper'],
    ],
  }

  if $hbacrules != undef or $automember {
    file { "/etc/ipa/group_rules_${name}.py":
      mode    => '0700',
      content => epp(
        'profile/freeipa/group_rules.py',
        {
          'group'      => $name,
          'automember' => $automember,
          'hbacrules'  => $hbacrules,
        }
      ),
    }
    exec { "group_rules_${name}":
      command     => "kinit_wrapper ipa console /etc/ipa/group_rules_${name}.py",
      refreshonly => true,
      require     => [
        File['kinit_wrapper'],
      ],
      environment => $environment,
      path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
      subscribe   => [
        File["/etc/ipa/group_rules_${name}.py"],
        Exec['hbac_rules'],
        Exec['ipa-install'],
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
) {
  $admin_password = lookup('profile::freeipa::server::admin_password')
  $group_args = join($groups.map |$group| { "--group ${group}" }, ' ')
  $sshpubkey_string = join($public_keys.map |$key| { "--sshpubkey '${key}'" }, ' ')
  $cmd_args = "${group_args} ${$sshpubkey_string}"
  if $count > 1 {
    $page_size = 50
    $prefix = $name
    $exec_name = range(1, $count, $page_size).map |$i| {
      "ldap_user_${name}_${i}-${min($i+$page_size, $count)}"
    }
    $command = range(1, $count, $page_size).map |$i| {
      "kinit_wrapper ipa_create_user.py $(seq -f'${prefix}%0${length(String($count))}g' ${i} ${min($count, $i+$page_size)}) ${cmd_args}"
    }
    $unless = $command.map|$cmd| { "${cmd} --dry" }
    $timeout = $page_size * 10
  } elsif $count == 1 {
    $exec_name = ["ldap_user_${name}"]
    $command = ["kinit_wrapper ipa_create_user.py ${name} ${cmd_args}"]
    $unless = ["${command} --dry"]
    $timeout = 10
  }

  $environment = ["IPA_ADMIN_PASSWD=${admin_password}"]

  if $count > 0 {
    $exec_name.each |Integer $i, String $exec_name_i| {
      exec { $exec_name_i:
        command     => $command[$i],
        unless      => $unless[$i],
        environment => $environment,
        path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
        timeout     => $timeout,
        require     => [
          File['kinit_wrapper'],
          File['/sbin/ipa_create_user.py'],
        ],
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
          "seq -f'${prefix}%0${length(String($count))}g' ${i} ${min($count, $i+$page_size)} | xargs -I '{}' ${ldad_passwd_cmd}"
        }
        $check_password_cmd = range(1, $count, $page_size).map |$i| {
          "echo ${passwd} | kinit $(seq -f'${prefix}%0${length(String($count))}g' ${i} ${min($count, $i+$page_size)} | shuf | head -n1) && kdestroy"
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
          subscribe   => Exec[$exec_name_i],
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
