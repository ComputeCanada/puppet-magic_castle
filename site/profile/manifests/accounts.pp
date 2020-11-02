class profile::accounts {
  require profile::freeipa::server
  require profile::nfs::server
  require profile::slurm::accounting

  file { '/sbin/ipa_create_user.py':
    source => 'puppet:///modules/profile/accounts/ipa_create_user.py',
    mode   => '0755'
  }

  file { '/sbin/mkhomedir.sh':
    source => 'puppet:///modules/profile/accounts/mkhomedir.sh',
    mode   => '0755'
  }

  file { 'mkhomedir_slapd.service':
    ensure => 'present',
    path   => '/lib/systemd/system/mkhomedir_slapd.service',
    source => 'puppet:///modules/profile/accounts/mkhomedir_slapd.service'
  }

  service { 'mkhomedir_slapd':
    ensure  => running,
    enable  => true,
    require => [
      File['/sbin/mkhomedir.sh'],
      File['mkhomedir_slapd.service'],
    ]
  }

  file { 'mkprojectdir_slapd.service':
    ensure => 'present',
    path   => '/lib/systemd/system/mkprojectdir_slapd.service',
    source => 'puppet:///modules/profile/accounts/mkprojectdir_slapd.service'
  }

  file { 'mkprojectdaemon.sh':
    ensure => 'present',
    path   => '/sbin/mkprojectdaemon.sh',
    source => 'puppet:///modules/profile/accounts/mkprojectdaemon.sh',
    mode   => '0755',
    owner  => 'root'
  }

  service { 'mkprojectdir_slapd':
    ensure  => running,
    enable  => true,
    require => [
      File['mkprojectdaemon.sh'],
      File['mkprojectdir_slapd.service'],
    ]
  }
}

class profile::accounts::guests(
  String $passwd,
  Integer $nb_accounts,
  String $prefix = 'user')
{
  require profile::accounts

  $admin_passwd = lookup('profile::freeipa::base::admin_passwd')
  exec{ 'ipa_add_user':
    command     => "kinit_wrapper ipa_create_user.py ${prefix}{01..${nb_accounts}} --sponsor=sponsor00",
    onlyif      => "test `stat -c '%U' /mnt/home/${prefix}{01..${nb_accounts}} | grep ${prefix} | wc -l` != ${nb_accounts}",
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}",
                    "IPA_GUEST_PASSWD=${passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
  }
}
