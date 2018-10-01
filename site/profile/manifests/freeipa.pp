class profile::freeipa::base (String $admin_passwd,
                              String $dns_ip,
                              String $domain_name)
{
  package { 'systemd':
    ensure => 'latest'
  }

  service { 'dbus':
    ensure => running,
    enable => true
  }

  file_line { 'resolv_search':
    ensure => present,
    path   => "/etc/resolv.conf",
    match  => "search",
    line   => "search $domain_name"
  }

  file_line { 'resolv_nameserver':
    ensure  => present,
    path    => "/etc/resolv.conf",
    after   => "search $domain_name",
    line    => "nameserver $dns_ip",
    require => File_line['resolv_search']
  }  
}

class profile::freeipa::client
{
  include profile::freeipa::base
  $domain_name = hiera("profile::freeipa::base::domain_name")
  $admin_passwd = hiera("profile::freeipa::base::admin_passwd")
  
  package { 'ipa-client':
    ensure => 'installed',
    notify => Service['dbus']
  }

  exec { 'set_hostname':
    command => "/bin/hostnamectl set-hostname $hostname.$domain_name",
    unless  => "/usr/bin/test `hostname` = $hostname.$domain_name"
  }

  exec { 'ipa-client-install':
    command => "/sbin/ipa-client-install \
                --mkhomedir \
                --ssh-trust-dns \
                --enable-dns-updates \
                --unattended \
                --force-join \
                -p admin \
                -w $admin_passwd",
    tries => 10,
    try_sleep => 30,
    require => [File_line['resolv_nameserver'],
                File_line['resolv_search'],
                Exec['set_hostname']],
    creates => '/etc/ipa/default.conf'
  }
}

class profile::freeipa::guest_accounts(String $guest_passwd,
                                       Integer $nb_accounts,
                                       String $prefix = "user")
{
  $admin_passwd = hiera("profile::freeipa::base::admin_passwd")

  selinux::module { 'mkhomedir_helper':
    ensure    => 'present',
    source_te => 'puppet:///modules/profile/freeipa/mkhomedir_helper.te',
    builder   => 'refpolicy'
  }

  file { '/sbin/ipa_create_user.sh':
    source => 'puppet:///modules/profile/freeipa/ipa_create_user.sh',
    mode   => '0700'
  }

  range("${prefix}01", "${prefix}${nb_accounts}").each |$user| {
    exec{ "add_$user":
      command     => "/sbin/ipa_create_user.sh $user",
      creates     => "/home/$user",
      environment => ["IPA_ADMIN_PASSWD=$admin_passwd",
                      "IPA_GUEST_PASSWD=$guest_passwd"],
      require     => [File['/sbin/ipa_create_user.sh'],
                      Selinux::Module['mkhomedir_helper'],
                      Exec['ipa-server-install']]
    }
  }
}

class profile::freeipa::server
{
  class { 'profile::freeipa::base':
    dns_ip => '127.0.0.1'
  }
  $domain_name = hiera("profile::freeipa::base::domain_name")
  $admin_passwd = hiera("profile::freeipa::base::admin_passwd")  

  package { "ipa-server-dns":
    ensure => "installed",
    notify => Service['dbus']
  }

  $realm = upcase($domain_name)
  $ip = $facts['networking']['ip']
  exec { 'ipa-server-install':
    command => "/sbin/ipa-server-install \
                --setup-dns \
                --hostname $hostname.$domain_name \
                --ds-password $admin_passwd \
                --admin-password $admin_passwd \
                --mkhomedir \
                --ssh-trust-dns \
                --unattended \
                --forwarder=1.1.1.1 \
                --forwarder=8.8.8.8 \
                --ip-address=$ip \
                --no-host-dns \
                --no-dnssec-validation \
                --real=$realm",
    creates => '/etc/ipa/default.conf',
    timeout => 0,
    require => [Package['ipa-server-dns'],
                Class['::swap_file']],
    before  => File_line['resolv_search']
  }
}
