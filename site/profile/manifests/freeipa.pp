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
    line   => "search int.$domain_name"
  }

  file_line { 'resolv_nameserver':
    ensure  => present,
    path    => "/etc/resolv.conf",
    after   => "search int.$domain_name",
    line    => "nameserver $dns_ip",
    require => File_line['resolv_search']
  }
}

class profile::freeipa::client
{
  include profile::freeipa::base
  $domain_name = lookup("profile::freeipa::base::domain_name")
  $admin_passwd = lookup("profile::freeipa::base::admin_passwd")
  $dns_ip = lookup("profile::freeipa::base::dns_ip")

  package { 'ipa-client':
    ensure => 'installed',
    notify => Service['dbus']
  }

  exec { 'set_hostname':
    command => "/bin/hostnamectl set-hostname $hostname.int.$domain_name",
    unless  => "/usr/bin/test `hostname` = $hostname.int.$domain_name"
  }

  tcp_conn_validator { 'ipa_dns':
    host      => $dns_ip,
    port      => 53,
    try_sleep => 10,
    timeout   => 1200,
  }

  exec { 'ipa-client-install':
    command   => "/sbin/ipa-client-install \
                  --mkhomedir \
                  --ssh-trust-dns \
                  --enable-dns-updates \
                  --unattended \
                  --force-join \
                  -p admin \
                  -w $admin_passwd",
    tries     => 10,
    try_sleep => 10,
    require   => [File_line['resolv_nameserver'],
                  File_line['resolv_search'],
                  Exec['set_hostname'],
                  Tcp_conn_validator['ipa_dns']],
    creates => '/etc/ipa/default.conf'
  }
}

class profile::freeipa::guest_accounts(String $guest_passwd,
                                       Integer $nb_accounts,
                                       String $prefix = "user")
{
  $admin_passwd = lookup("profile::freeipa::base::admin_passwd")

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
    exec{ "ipa_add_$user":
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
  $domain_name = lookup("profile::freeipa::base::domain_name")
  $admin_passwd = lookup("profile::freeipa::base::admin_passwd")

  package { "ipa-server-dns":
    ensure => "installed",
    notify => Service['dbus']
  }

  $realm = upcase("int.$domain_name")
  $ip = $facts['networking']['ip']
  exec { 'ipa-server-install':
    command => "/sbin/ipa-server-install \
                --setup-dns \
                --hostname $hostname.int.$domain_name \
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
                --no-ui-redirect \
                --no-pkinit \
                --no-ntp \
                --real=$realm",
    creates => '/etc/ipa/default.conf',
    timeout => 0,
    require => [Package['ipa-server-dns']],
    before  => File_line['resolv_search']
  }
}
