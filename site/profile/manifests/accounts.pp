class profile::accounts {
  require profile::freeipa::server
  require profile::freeipa::mokey
  require profile::nfs::server
  require profile::slurm::accounting

  file { '/sbin/ipa_create_user.py':
    source => 'puppet:///modules/profile/accounts/ipa_create_user.py',
    mode   => '0755'
  }

  file { '/sbin/mkhome.sh':
    ensure => 'present',
    source => 'puppet:///modules/profile/accounts/mkhome.sh',
    mode   => '0755',
    owner  => 'root',
  }

  file { 'mkhome.service':
    ensure => 'present',
    path   => '/lib/systemd/system/mkhome.service',
    source => 'puppet:///modules/profile/accounts/mkhome.service'
  }

  service { 'mkhome':
    ensure    => running,
    enable    => true,
    subscribe => [
      File['/sbin/mkhome.sh'],
      File['mkhome.service'],
    ]
  }

  file { 'mkproject.service':
    ensure => 'present',
    path   => '/lib/systemd/system/mkproject.service',
    source => 'puppet:///modules/profile/accounts/mkproject.service'
  }

  file { '/sbin/mkproject.sh':
    ensure => 'present',
    source => 'puppet:///modules/profile/accounts/mkproject.sh',
    mode   => '0755',
    owner  => 'root',
  }

  if defined(File['/mnt/project']) {
    service { 'mkproject':
      ensure    => running,
      enable    => true,
      subscribe => [
        File['/sbin/mkproject.sh'],
        File['mkproject.service'],
      ]
    }
  }
}

class profile::accounts::guests(
  String[8] $passwd,
  Integer[0] $nb_accounts,
  String[1] $prefix = 'user',
  String[3] $sponsor = 'sponsor00'
  )
{
  require profile::accounts

  $admin_passwd = lookup('profile::freeipa::base::admin_passwd')
  if $nb_accounts > 0 {
    exec{ 'ipa_add_user':
      command     => "kinit_wrapper ipa_create_user.py $(seq -w ${nb_accounts} | sed 's/^/${prefix}/') --sponsor=${$sponsor}",
      onlyif      => "test $(stat -c '%U' $(seq -w ${nb_accounts} | sed 's/^/\\/mnt\\/home\\/${prefix}/') | grep ${prefix} | wc -l) != ${nb_accounts}",
      environment => ["IPA_ADMIN_PASSWD=${admin_passwd}",
                      "IPA_GUEST_PASSWD=${passwd}"],
      path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
      timeout     => $nb_accounts * 10,
    }
  }
}
