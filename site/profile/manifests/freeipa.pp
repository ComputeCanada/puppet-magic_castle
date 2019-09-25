class profile::freeipa::base (
  String $admin_passwd,
  String $dns_ip,
  String $domain_name)
{
  package { 'systemd':
    ensure => 'latest'
  }

  service { 'NetworkManager':
    ensure => stopped,
    enable => false
  }

  package { [
    'NetworkManager',
    'NetworkManager-tui',
    'NetworkManager-team'
    ]:
    ensure => purged
  }

  service { 'systemd-logind':
    ensure => running,
    enable => true
  }

  file { 'kinit_wrapper':
    ensure => present,
    path   => '/usr/bin/kinit_wrapper',
    source => 'puppet:///modules/profile/freeipa/kinit_wrapper',
    mode   => '0755'
  }

  file { '/etc/dhclient.conf':
    ensure => absent
  }

  file { 'dhclient.conf':
    ensure  => present,
    path    => '/etc/dhcp/dhclient.conf',
    mode    => '0644',
    require => Service['NetworkManager'],
    content => @("END")
# Set the dhclient retry interval to 10 seconds instead of 5 minutes.
retry 10;
prepend domain-search "int.${domain_name}";
prepend domain-name-servers ${dns_ip};
END
  }

  file_line { 'resolv_search':
    ensure  => present,
    path    => '/etc/resolv.conf',
    match   => 'search',
    line    => "search int.${domain_name}",
    require => File['dhclient.conf']
  }

  file_line { 'resolv_nameserver':
    ensure  => present,
    path    => '/etc/resolv.conf',
    after   => "search int.${domain_name}",
    line    => "nameserver ${dns_ip}",
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
    line   => "DNS1=${dns_ip}"
  }

  file { '/etc/rsyslog.d/ignore-systemd-session-slice.conf':
    ensure => present,
    source => 'puppet:///modules/profile/freeipa/ignore-systemd-session-slice.conf',
    mode   => '0644'
  }

}

class profile::freeipa::client(String $server_ip)
{
  class { 'profile::freeipa::base':
    dns_ip => $server_ip
  }

  $domain_name = lookup('profile::freeipa::base::domain_name')
  $int_domain_name = "int.${domain_name}"
  $admin_passwd = lookup('profile::freeipa::base::admin_passwd')
  $fqdn = "${::hostname}.${int_domain_name}"
  $realm = upcase($int_domain_name)

  package { 'ipa-client':
    ensure => 'installed'
  }

  exec { 'set_hostname':
    command => "/bin/hostnamectl set-hostname ${fqdn}",
    unless  => "/usr/bin/test `hostname` = ${fqdn}"
  }

  tcp_conn_validator { 'ipa_dns':
    host      => $server_ip,
    port      => 53,
    try_sleep => 10,
    timeout   => 1200,
  }

  tcp_conn_validator { 'ipa_ldap':
    host      => $server_ip,
    port      => 389,
    try_sleep => 10,
    timeout   => 1200,
  }

  $ipa_client_install_cmd = @("IPACLIENTINSTALL"/L)
      /sbin/ipa-client-install \
      --mkhomedir \
      --ssh-trust-dns \
      --enable-dns-updates \
      --unattended \
      --force-join \
      -p admin \
      -w ${admin_passwd}
      | IPACLIENTINSTALL

  exec { 'ipa-client-install':
    command   => Sensitive($ipa_client_install_cmd),
    tries     => 10,
    try_sleep => 10,
    require   => [File_line['resolv_nameserver'],
                  File_line['resolv_search'],
                  Exec['set_hostname'],
                  Tcp_conn_validator['ipa_dns'],
                  Tcp_conn_validator['ipa_ldap']],
    creates   => '/etc/ipa/default.conf',
    notify    => Service['systemd-logind']
  }

  $reverse_zone = profile::getreversezone()
  $ptr_record = profile::getptrrecord()

  exec { 'ipa_dnsrecord-del_ptr':
    command     => "kinit_wrapper ipa dnsrecord-del ${reverse_zone} ${ptr_record} --del-all",
    onlyif      => "test `dig -x ${::ipaddress_eth0} | grep -oP '^.*\\s[0-9]*\\sIN\\sPTR\\s\\K(.*)'` != ${fqdn}.",
    require     => [File['kinit_wrapper'], Exec['ipa-client-install']],
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin']
  }

  exec { 'ipa_dnsrecord-add_ptr':
    command     => "kinit_wrapper ipa dnsrecord-add ${reverse_zone} ${ptr_record} --ptr-hostname=${fqdn}.",
    unless      => "dig -x ${::ipaddress_eth0} | grep -q ';; ANSWER SECTION:'",
    require     => [File['kinit_wrapper'], Exec['ipa-client-install'], Exec['ipa_dnsrecord-del_ptr']],
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin']
  }

  service { 'sssd':
    ensure  => running,
    enable  => true,
    require => Exec['ipa-client-install']
  }

  # If selinux_provider is ipa, each time a new
  # user logs in, the selinux policy is rebuilt.
  # This can cause serious slow down when multiple
  # concurrent users try to login at the same time
  # since the rebuilt is done for each user sequentially.
  file_line { 'selinux_provider':
    ensure  => present,
    path    => '/etc/sssd/sssd.conf',
    after   => 'id_provider = ipa',
    line    => 'selinux_provider = none',
    require => Exec['ipa-client-install'],
    notify  => Service['sssd']
  }

  # Configure default login selinux mapping
  exec { 'selinux_login_default':
    command => 'semanage login -m -S targeted -s "user_u" -r s0 __default__',
    unless  => 'grep -q "__default__:user_u:s0" /etc/selinux/targeted/seusers',
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    require => Exec['ipa-client-install']
  }

  # If the ipa-server is reinstalled, the ipa-client needs to be reinstalled too.
  # The installation is only done if the certificate on the ipa-server no
  # longer corresponds to the one currently installed on the client. When this
  # happens, curl returns a code 35.
  exec { 'ipa-client-uninstall':
    command => '/sbin/ipa-client-install -U --uninstall',
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    onlyif  => ['test -f /etc/ipa/default.conf',
                'curl --silent $(grep -oP "xmlrpc_uri = \K(.*)" /etc/ipa/default.conf); test $? -eq 35']
  }

}

class profile::freeipa::guest_accounts(
  String $guest_passwd,
  Integer $nb_accounts,
  String $prefix = 'user')
{
  $admin_passwd = lookup('profile::freeipa::base::admin_passwd')

  file { '/sbin/ipa_create_user.py':
    source => 'puppet:///modules/profile/freeipa/ipa_create_user.py',
    mode   => '0755'
  }

  file { '/sbin/mkhomedir.sh':
    source => 'puppet:///modules/profile/freeipa/mkhomedir.sh',
    mode   => '0755'
  }

  exec { 'semanage_fcontext_mnt_home':
    command => 'semanage fcontext -a -e /home /mnt/home',
    unless  => 'grep -q "/mnt/home\s*/home" /etc/selinux/targeted/contexts/files/file_contexts.subs*',
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin']
  }

  exec{ 'ipa_add_user':
    command     => "kinit_wrapper ipa_create_user.py ${prefix}{01..${nb_accounts}} --sponsor=sponsor00",
    onlyif      => "test `stat -c '%U' /mnt/home/${prefix}{01..${nb_accounts}} | grep ${prefix} | wc -l` != ${nb_accounts}",
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}",
                    "IPA_GUEST_PASSWD=${guest_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    require     => [File['/sbin/ipa_create_user.py'],
                    File['kinit_wrapper'],
                    Exec['ipa-server-install']]
  }

  exec{ 'mkhomedir':
    command => "/sbin/mkhomedir.sh  ${prefix}{01..${nb_accounts}}",
    unless  => "ls /mnt/home/${prefix}{01..${nb_accounts}} &> /dev/null",
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    require => [Exec['ipa_add_user'],
                Exec['semanage_fcontext_mnt_home']],
  }
}

class profile::freeipa::server
{
  class { 'profile::freeipa::base':
    dns_ip => '127.0.0.1'
  }
  $domain_name = lookup('profile::freeipa::base::domain_name')
  $admin_passwd = lookup('profile::freeipa::base::admin_passwd')

  package { 'ipa-server-dns':
    ensure => 'installed'
  }

  $int_domain_name = "int.${domain_name}"
  $realm = upcase($int_domain_name)
  $fqdn = "${::hostname}.${int_domain_name}"
  $reverse_zone = profile::getreversezone()

  # Remove hosts entry only once before install FreeIPA
  exec { 'remove-hosts-entry':
    command => "/usr/bin/sed -i '/${::ipaddress_eth0}/d' /etc/hosts",
    before  => Exec['ipa-server-install'],
    unless  => ['/usr/bin/test -f /var/log/ipaserver-install.log']
  }


  $ipa_server_install_cmd = @("IPASERVERINSTALL"/L)
      /sbin/ipa-server-install \
      --setup-dns \
      --hostname ${fqdn} \
      --ds-password ${admin_passwd} \
      --admin-password ${admin_passwd} \
      --mkhomedir \
      --idstart=50000 \
      --ssh-trust-dns \
      --unattended \
      --auto-forwarders \
      --ip-address=${::ipaddress_eth0} \
      --no-host-dns \
      --no-dnssec-validation \
      --no-ui-redirect \
      --no-pkinit \
      --no-ntp \
      --allow-zone-overlap \
      --reverse-zone=${reverse_zone} \
      --realm=${realm} \
      --domain=${int_domain_name}
      | IPASERVERINSTALL

  exec { 'ipa-server-install':
    command => Sensitive($ipa_server_install_cmd),
    creates => '/etc/ipa/default.conf',
    timeout => 0,
    require => [Package['ipa-server-dns']],
    before  => File_line['resolv_search'],
    notify  => Service['systemd-logind']
  }

  exec { 'ipa_config-mod_auth-otp':
    command     => 'kinit_wrapper ipa config-mod --user-auth-type=otp',
    refreshonly => true,
    require     => [File['kinit_wrapper'], Exec['ipa-server-install']],
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin']
  }

  service { 'ipa':
    ensure  => running,
    enable  => true,
    require => Exec['ipa-server-install']
  }
}
