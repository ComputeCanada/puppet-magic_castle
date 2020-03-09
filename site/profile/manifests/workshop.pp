class profile::workshop {

}

class profile::workshop::mgmt {
  $userzip_url = lookup({ name =>'profile::workshop::userzip_url', default_value => '' })
  $userzip_path = lookup({ name => 'profile::workshop::userzip_path', default_value => '/project/userzip.zip' })
  $nb_accounts = lookup({ name => 'profile::freeipa::guest_accounts::nb_accounts', default_value => 0 })
  $prefix      = lookup({ name => 'profile::freeipa::guest_accounts::prefix', default_value => 'user' })
  $nb_zeros    = inline_template("<%= '0' * ('${nb_accounts}'.length - 1) %>")
  $user_range  = "${prefix}{${nb_zeros}1..${nb_accounts}}"

  if ($userzip_url != '') {
    file { $userzip_path:
      ensure => 'present',
      source => $userzip_url,
    }

    exec { 'workshop_unzip_to_user_home':
      command     => "for user in ${user_range}; do unzip -f -o \"${userzip_path}\" -d /mnt/home/\$user; done",
      require     => [Class['profile::freeipa::guest_accounts'], Mount['/mnt/home']],
      subscribe   => File[$userzip_path],
      refreshonly => true,
      path        => ['/bin', '/usr/sbin'],
      provider    => shell,
    }
    exec { 'workshop_chown_user':
      command     => "for user in ${user_range}; do chown -R \$user:\$user /mnt/home/\$user; chmod -R u+rw /mnt/home/\$user; done",
      require     => Mount['/mnt/home'],
      subscribe   => Exec['workshop_unzip_to_user_home'],
      refreshonly => true,
      path        => ['/bin', '/usr/sbin'],
      provider    => shell,
    }
  }
}
