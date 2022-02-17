class profile::workshop {

}

class profile::workshop::mgmt {
  $userzip_url = lookup({ name =>'profile::workshop::userzip_url', default_value => '' })
  $userzip_path = lookup({ name => 'profile::workshop::userzip_path', default_value => '/mnt/project/userzip.zip' })

  if ($userzip_url != '') {
    file { $userzip_path:
      ensure => 'present',
      source => $userzip_url,
    }

    exec { 'workshop_unzip_to_ldap_user_home':
      command     => "for user in $(ls /mnt/home/); do unzip -f -o \"${userzip_path}\" -d /mnt/home/\$user; done",
      require     => [Class['profile::users::ldap'], Mount['/mnt/home']],
      subscribe   => File[$userzip_path],
      refreshonly => true,
      path        => ['/bin', '/usr/sbin'],
      provider    => shell,
    }
    exec { 'workshop_chown_user':
      command     => "for user in $(ls /mnt/home/); do chown -R \$user:\$user /mnt/home/\$user; chmod -R u+rw /mnt/home/\$user; done",
      require     => Mount['/mnt/home'],
      subscribe   => Exec['workshop_unzip_to_ldap_user_home'],
      refreshonly => true,
      path        => ['/bin', '/usr/sbin'],
      provider    => shell,
    }
  }
}
