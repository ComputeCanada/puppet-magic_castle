class profile::freeipa::base (
  String $admin_passwd,
  String $dns_ip,
  String $domain_name)
{

  if dig($::facts, 'os', 'release', 'major') == '8' {
    exec { 'enable_idm:DL1':
      command => 'yum module enable -y idm:DL1',
      creates => '/etc/dnf/modules.d/idm.module',
      path    => ['/usr/bin', '/usr/sbin']
    }

    package { 'network-scripts':
      ensure => 'installed'
    }
  }

  package { 'systemd':
    ensure => 'latest'
  }

  service { 'NetworkManager':
    ensure => stopped,
    enable => false
  }

  service { 'network':
    ensure => running,
    enable => true,
  }

  package { [
    'NetworkManager',
    'NetworkManager-tui',
    'NetworkManager-team'
    ]:
    ensure => purged,
    notify => Service['network'],
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
    notify  => Service['network'],
    content => @("END")
# Set the dhclient retry interval to 10 seconds instead of 5 minutes.
retry 10;
prepend domain-search "int.${domain_name}";
prepend domain-name-servers ${dns_ip};
END
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
  $interface = split($::interfaces, ',')[0]
  $ipaddress = $::networking['interfaces'][$interface]['ip']

  package { 'ipa-client':
    ensure => 'installed'
  }

  $ipa_records = [
    "_kerberos-master._tcp.${int_domain_name} SRV",
    "_kerberos-master._udp.${int_domain_name} SRV",
    "_kerberos._tcp.${int_domain_name} SRV",
    "_kerberos._udp.${int_domain_name} SRV",
    "_kpasswd._tcp.${int_domain_name} SRV",
    "_kpasswd._udp.${int_domain_name} SRV",
    "_ldap._tcp.${int_domain_name} SRV",
    "ipa-ca.${int_domain_name} A"
  ]

  wait_for { 'ipa_records':
    query             => sprintf('dig +short %s | wc -l', join($ipa_records, ' ')),
    regex             => String(length($ipa_records)),
    polling_frequency => 10,
    max_retries       => 60,
    refreshonly       => true,
    subscribe         => [Package['ipa-client'], Exec['ipa-client-uninstall']]
  }

  # Check if the FreeIPA HTTPD service is consistently available
  # over a period of 2sec * 15 times = 30 seconds. If a single
  # test of availability fails, we wait for 5 seconds, then try
  # again.
  wait_for { 'ipa-ca_https':
    query             => "for i in {1..15}; do curl --insecure -L --silent --output /dev/null https://ipa-ca.${int_domain_name}/ && sleep 2 || exit 1; done",
    exit_code         => 0,
    polling_frequency => 5,
    max_retries       => 60,
    refreshonly       => true,
    subscribe         => Wait_for['ipa_records']
  }

  exec { 'set_hostname':
    command => "/bin/hostnamectl set-hostname ${fqdn}",
    unless  => "/usr/bin/test `hostname` = ${fqdn}"
  }

  $ipa_client_install_cmd = @("IPACLIENTINSTALL"/L)
      /sbin/ipa-client-install \
      --domain ${int_domain_name} \
      --hostname ${fqdn} \
      --ip-address ${ipaddress} \
      --ssh-trust-dns \
      --unattended \
      --force-join \
      -p admin \
      -w ${admin_passwd}
      | IPACLIENTINSTALL

  exec { 'ipa-client-install':
    command   => Sensitive($ipa_client_install_cmd),
    tries     => 2,
    try_sleep => 60,
    require   => [File['dhclient.conf'],
                  Exec['set_hostname'],
                  Wait_for['ipa-ca_https']],
    creates   => '/etc/ipa/default.conf',
    notify    => Service['systemd-logind']
  }

  $reverse_zone = profile::getreversezone()
  $ptr_record = profile::getptrrecord()

  exec { 'ipa_dnsrecord-del_ptr':
    command     => "kinit_wrapper ipa dnsrecord-del ${reverse_zone} ${ptr_record} --del-all",
    onlyif      => "test `dig -x ${ipaddress} | grep -oP '^.*\\s[0-9]*\\sIN\\sPTR\\s\\K(.*)'` != ${fqdn}.",
    require     => [File['kinit_wrapper'], Exec['ipa-client-install']],
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin']
  }

  exec { 'ipa_dnsrecord-add_ptr':
    command     => "kinit_wrapper ipa dnsrecord-add ${reverse_zone} ${ptr_record} --ptr-hostname=${fqdn}.",
    unless      => "dig -x ${ipaddress} | grep -q ';; ANSWER SECTION:'",
    require     => [File['kinit_wrapper'], Exec['ipa-client-install'], Exec['ipa_dnsrecord-del_ptr']],
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    tries       => 5,
    try_sleep   => 10,
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
    require => [
      Exec['ipa_add_user'],
      Exec['semanage_fcontext_mnt_home'],
      Exec['semanage_fcontext_project'],
      Exec['semanage_fcontext_scratch'],
    ],
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

  $interface = split($::interfaces, ',')[0]
  $ipaddress = $::networking['interfaces'][$interface]['ip']

  # Remove host entry only once before install FreeIPA
  exec { 'remove-hosts-entry':
    command => "/usr/bin/sed -i '/${ipaddress}/d' /etc/hosts",
    before  => Exec['ipa-server-install'],
    unless  => ['/usr/bin/test -f /var/log/ipaserver-install.log']
  }

  # Make sure the FQDN is set in /etc/hosts to avoid any resolve
  # issue when install FreeIPA server
  host { $fqdn:
    ip           => $ipaddress,
    host_aliases => [$::hostname],
    require      => Exec['remove-hosts-entry'],
    before       => Exec['ipa-server-install'],
  }

  $ipa_server_install_cmd = @("IPASERVERINSTALL"/L)
      /sbin/ipa-server-install \
      --setup-dns \
      --hostname ${fqdn} \
      --ds-password ${admin_passwd} \
      --admin-password ${admin_passwd} \
      --idstart=${facts['uid_max']} \
      --ssh-trust-dns \
      --unattended \
      --auto-forwarders \
      --ip-address=${ipaddress} \
      --no-host-dns \
      --no-dnssec-validation \
      --no-ui-redirect \
      --no-pkinit \
      --no-ntp \
      --allow-zone-overlap \
      --reverse-zone=${reverse_zone} \
      --realm=${realm} \
      --domain=${int_domain_name} \
      --no_hbac_allow
      | IPASERVERINSTALL

  exec { 'ipa-server-install':
    command => Sensitive($ipa_server_install_cmd),
    creates => '/etc/ipa/default.conf',
    timeout => 0,
    require => [Package['ipa-server-dns']],
    before  => File['dhclient.conf'],
    notify  => Service['systemd-logind']
  }

  exec { 'ipa_config-mod_auth-otp':
    command     => 'kinit_wrapper ipa config-mod --user-auth-type=otp',
    refreshonly => true,
    require     => [File['kinit_wrapper'],],
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-server-install']
  }

  exec { 'ipa_automember_ipausers':
    command     => 'kinit_wrapper ipa automember-default-group-set --default-group=ipausers --type=group',
    refreshonly => true,
    require     => [File['kinit_wrapper'], ],
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-server-install']
  }

  exec { 'ipa_hostgroup_not_mgmt':
    command     => 'kinit_wrapper ipa hostgroup-add not_mgmt',
    refreshonly => true,
    require     => [File['kinit_wrapper'], Exec['ipa-server-install']],
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-server-install']
  }
  ~> exec { 'ipa_automember_not_mgmt':
    command     => 'kinit_wrapper ipa automember-add not_mgmt --type=hostgroup',
    refreshonly => true,
    require     => [File['kinit_wrapper'], Exec['ipa-server-install']],
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin']
  }
  ~> exec { 'ipa_automember_condition_not_mgmt':
    command     => 'kinit_wrapper ipa automember-add-condition not_mgmt --type=hostgroup --key=fqdn --inclusive-regex=.* --exclusive-regex="^mgmt.*"',
    refreshonly => true,
    require     => [File['kinit_wrapper'], Exec['ipa-server-install']],
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin']
  }
  ~> exec { 'ipa_automember_rebuild_hostgroup':
    command     => 'kinit_wrapper ipa automember-rebuild --type=hostgroup',
    refreshonly => true,
    require     => [File['kinit_wrapper'], Exec['ipa-server-install']],
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin']
  }

  exec { 'ipa_hbacrule_notmgmt':
    command     => 'kinit_wrapper ipa hbacrule-add ipauser_not_mgmt --servicecat=all',
    refreshonly => true,
    require     => [File['kinit_wrapper'],],
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-server-install']
  }

  exec { 'ipa_hbacrule_notmgmt_addusers':
    command     => 'kinit_wrapper ipa hbacrule-add-user ipauser_not_mgmt --groups=ipausers',
    refreshonly => true,
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    require     => [File['kinit_wrapper'],],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => [Exec['ipa_hbacrule_notmgmt'], Exec['ipa_automember_ipausers']]
  }

  exec { 'ipa_hbacrule_notmgmt_addhosts':
    command     => 'kinit_wrapper ipa hbacrule-add-host ipauser_not_mgmt --hostgroups=not_mgmt',
    refreshonly => true,
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    require     => [File['kinit_wrapper'],],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => [Exec['ipa_hbacrule_notmgmt'], Exec['ipa_hostgroup_not_mgmt']]
  }

  exec { 'ipa_add_record_CNAME':
    command     => "kinit_wrapper ipa dnsrecord-add ${int_domain_name} ipa --cname-rec ${::hostname}",
    refreshonly => true,
    require     => [File['kinit_wrapper'], ],
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-server-install'],
  }

  exec { 'ipa_add_host_ipa':
    command     => "kinit_wrapper ipa host-add ipa.${int_domain_name} --force",
    refreshonly => true,
    require     => [File['kinit_wrapper'], ],
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-server-install'],
  }

  exec { 'ipa_add_service_principal':
    command     => "kinit_wrapper ipa service-add-principal HTTP/${fqdn} HTTP/ipa.${int_domain_name}",
    refreshonly => true,
    require     => [
      File['kinit_wrapper'],
      Exec['ipa_add_record_CNAME'],
      Exec['ipa_add_host_ipa'],
    ],
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-server-install'],
  }

  $regen_cert_cmd = lookup('profile::freeipa::server::regen_cert_cmd')
  exec { 'ipa_regen_server-cert':
    command     => "kinit_wrapper ${regen_cert_cmd} -D ipa.${int_domain_name}",
    refreshonly => true,
    require     => [
      File['kinit_wrapper'],
      Exec['ipa_add_service_principal'],
    ],
    environment => ["IPA_ADMIN_PASSWD=${admin_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-server-install'],
  }

  service { 'ipa':
    ensure  => running,
    enable  => true,
    require => Exec['ipa-server-install'],
  }

  service { 'httpd':
    ensure  => running,
    enable  => true,
    require => Exec['ipa-server-install'],
  }

  file { '/etc/httpd/conf.d/ipa-rewrite.conf':
    content => epp(
      'profile/freeipa/ipa-rewrite.conf',
      {
        'referee' => $fqdn,
        'referer' => "ipa.${domain_name}",
      }
    ),
    notify  => Service['httpd'],
    require => Exec['ipa-server-install'],
  }

}

class profile::freeipa::mokey
{

  package { 'mokey':
    ensure   => 'installed',
    name     => 'mokey-0.5.4-1.el7.x86_64',
    provider => 'rpm',
    source   => 'https://github.com/ubccr/mokey/releases/download/v0.5.4/mokey-0.5.4-1.el7.x86_64.rpm'
  }

  $password = lookup('profile::freeipa::base::admin_passwd')
  mysql::db { 'mokey':
    ensure   => present,
    user     => 'mokey',
    password => $password,
    host     => 'localhost',
    grant    => ['ALL'],
  }

  exec { 'mysql_mokey_schema':
    command     => Sensitive("mysql -u mokey -p${password} mokey < /usr/share/mokey/ddl/schema.sql"),
    refreshonly => true,
    require     => [
      Package['mokey'],
    ],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Mysql::Db['mokey'],
  }

}
