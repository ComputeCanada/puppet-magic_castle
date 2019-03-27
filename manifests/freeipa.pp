class profile::freeipa::base (String $admin_passwd,
                              String $dns_ip,
                              String $domain_name)
{
  package { 'systemd':
    ensure => 'latest'
  }

  service { 'systemd-logind':
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

  file_line { 'peerdns':
    ensure => present,
    path   => '/etc/sysconfig/network-scripts/ifcfg-eth0',
    line   => 'PEERDNS=no'
  }

  file_line { 'ifcfg_dns1':
    ensure => present,
    path   => '/etc/sysconfig/network-scripts/ifcfg-eth0',
    line   => "DNS1=$dns_ip"
  }

  file { '/etc/rsyslog.d/ignore-systemd-session-slice.conf':
    ensure  => present,
    source => 'puppet:///modules/profile/freeipa/ignore-systemd-session-slice.conf',
    mode   => '0644'
  }

}

class profile::freeipa::client(String $server = "mgmt01")
{
  include profile::freeipa::base
  $domain_name = lookup("profile::freeipa::base::domain_name")
  $admin_passwd = lookup("profile::freeipa::base::admin_passwd")
  $dns_ip = lookup("profile::freeipa::base::dns_ip")

  package { 'ipa-client':
    ensure => 'installed'
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

  tcp_conn_validator { 'ipa_ldap':
    host      => $dns_ip,
    port      => 389,
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
                  Tcp_conn_validator['ipa_dns'],
                  Tcp_conn_validator['ipa_ldap']],
    creates => '/etc/ipa/default.conf',
    notify  => Service['systemd-logind']
  }

  # If the ipa-server is reinstalled, the ipa-client needs to be reinstall too.
  # The installation is only done if the certificate on the ipa-server no
  # longer corresponds to the one currently installed on the client. When this
  # happens, curl returns a code 35.
  exec { 'ipa-client-uninstall':
    command => '/sbin/ipa-client-install -U --uninstall',
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    onlyif  => ['test -f /etc/ipa/default.conf',
                "curl --silent https://$server.int.$domain_name/ipa/json; test $? == 35"]
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

  exec{ "ipa_add_user":
    command     => "ipa_create_user.sh ${prefix}{01..${nb_accounts}} Sponsor=sponsor00",
    unless      => "test `ls /mnt/home | grep ${prefix} | wc -l` == ${nb_accounts}",
    environment => ["IPA_ADMIN_PASSWD=$admin_passwd",
                    "IPA_GUEST_PASSWD=$guest_passwd"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    require     => [File['/sbin/ipa_create_user.sh'],
                    Selinux::Module['mkhomedir_helper'],
                    Exec['ipa-server-install']],
    provider    => shell,
    timeout     => 0
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
    ensure => "installed"
  }

  $realm = upcase("int.$domain_name")
  $ip = $facts['networking']['ip']

  # Remove hosts entry only once before install FreeIPA
  exec { 'remove-hosts-entry':
    command => "/usr/bin/sed -i '/$ip/d' /etc/hosts",
    before  => Exec['ipa-server-install'],
    unless  => ['/usr/bin/test -f /var/log/ipaserver-install.log']
  }

  exec { 'ipa-server-install':
    command => "/sbin/ipa-server-install \
                --setup-dns \
                --hostname $hostname.int.$domain_name \
                --ds-password $admin_passwd \
                --admin-password $admin_passwd \
                --mkhomedir \
                --idstart=50000 \
                --ssh-trust-dns \
                --unattended \
                --auto-forwarders \
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
    before  => File_line['resolv_search'],
    notify  => Service['systemd-logind']
  }
}
