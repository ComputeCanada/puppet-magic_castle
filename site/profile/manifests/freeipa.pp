class profile::freeipa::base (String $domain_name) {
  if dig($::facts, 'os', 'release', 'major') == '8' {
    exec { 'enable_idm:DL1':
      command => 'yum module enable -y idm:DL1',
      creates => '/etc/dnf/modules.d/idm.module',
      path    => ['/usr/bin', '/usr/sbin']
    }
  }

  package { 'systemd':
    ensure => 'latest'
  }

  package { 'NetworkManager':
    ensure => present,
  }

  service { 'NetworkManager':
    ensure  => running,
    enable  => true,
    require => Package['NetworkManager'],
  }

  service { 'systemd-logind':
    ensure => running,
    enable => true
  }

  file { '/etc/rsyslog.d/ignore-systemd-session-slice.conf':
    ensure => present,
    source => 'puppet:///modules/profile/freeipa/ignore-systemd-session-slice.conf',
    mode   => '0644'
  }

}

class profile::freeipa::client(String $server_ip) {
  include profile::freeipa::base
  $domain_name = lookup('profile::freeipa::base::domain_name')
  $int_domain_name = "int.${domain_name}"
  $admin_password = lookup('profile::freeipa::server::admin_password')
  $fqdn = "${::hostname}.${int_domain_name}"
  $realm = upcase($int_domain_name)
  $interface = split($::interfaces, ',')[0]
  $ipaddress = $::networking['interfaces'][$interface]['ip']

  file { '/etc/NetworkManager/conf.d/zzz-puppet.conf':
    mode    => '0644',
    content => epp(
      'profile/freeipa/zzz-puppet.conf',
      {
        'int_domain_name' => $int_domain_name,
        'nameservers'     => union([$server_ip], $::nameservers),
      }),
    notify  => Service['NetworkManager'],
  }

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
    subscribe         => [
      Package['ipa-client'],
      Exec['ipa-client-uninstall_bad-hostname'],
      Exec['ipa-client-uninstall_bad-server']
    ]
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

  file { '/sbin/mc-ipa-client-install':
    ensure => 'present',
    mode   => '0755',
    source => 'puppet:///modules/profile/freeipa/mc-ipa-client-install',
  }

  $ipa_client_install_cmd = @("IPACLIENTINSTALL"/L)
      /sbin/mc-ipa-client-install \
      --domain ${int_domain_name} \
      --hostname ${fqdn} \
      --ip-address ${ipaddress} \
      --ssh-trust-dns \
      --unattended \
      --force-join \
      -p admin \
      -w ${admin_password}
      | IPACLIENTINSTALL

  exec { 'ipa-install':
    command   => Sensitive($ipa_client_install_cmd),
    tries     => 2,
    try_sleep => 60,
    require   => [
      File['/sbin/mc-ipa-client-install'],
      File['/etc/NetworkManager/conf.d/zzz-puppet.conf'],
      Exec['set_hostname'],
      Wait_for['ipa-ca_https'],
    ],
    creates   => '/etc/ipa/default.conf',
    notify    => Service['systemd-logind'],
  }

  file_line { 'ssh_known_hosts':
    ensure    => present,
    path      => '/etc/ssh/ssh_config.d/04-ipa.conf',
    match     => '^GlobalKnownHostsFile',
    line      => 'GlobalKnownHostsFile /var/lib/sss/pubconf/known_hosts /etc/ssh/ssh_known_hosts',
    subscribe => Exec['ipa-install']
  }

  # Configure default login selinux mapping
  exec { 'selinux_login_default':
    command => 'semanage login -m -S targeted -s "user_u" -r s0 __default__',
    unless  => 'grep -q "__default__:user_u:s0" /etc/selinux/targeted/seusers',
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    require => Exec['ipa-install']
  }

  # If the ipa-server is reinstalled, the ipa-client needs to be reinstalled too.
  # The installation is only done if the certificate on the ipa-server no
  # longer corresponds to the one currently installed on the client. When this
  # happens, curl returns a code 35.
  $uninstall_cmd = '/sbin/ipa-client-install -U --uninstall'
  exec { 'ipa-client-uninstall_bad-server':
    command => $uninstall_cmd,
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    onlyif  => [
      'test -f /etc/ipa/default.conf',
      'curl --silent $(grep -oP "xmlrpc_uri = \K(.*)" /etc/ipa/default.conf); test $? -eq 35'
    ],
    before  => Exec['ipa-install'],
  }
  # If the ipa-client is already installed in the image, it has potentially the wrong hostname.
  # In this case, the ipa-client needs to be reinstalled.
  exec { 'ipa-client-uninstall_bad-hostname':
    command => $uninstall_cmd,
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    onlyif  => ['test -f /etc/ipa/default.conf'],
    unless  => ["grep -q 'host = ${fqdn}' /etc/ipa/default.conf"],
    before  => Exec['ipa-install'],
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
    require => Exec['ipa-install'],
    notify  => Service['sssd']
  }

}

class profile::freeipa::server(
  String $admin_password,
  String $ds_password,
) {
  include profile::freeipa::base

  file { 'kinit_wrapper':
    ensure => present,
    path   => '/usr/bin/kinit_wrapper',
    source => 'puppet:///modules/profile/freeipa/kinit_wrapper',
    mode   => '0755'
  }

  $domain_name = lookup('profile::freeipa::base::domain_name')

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
    before  => Exec['ipa-install'],
    unless  => ['/usr/bin/test -f /var/log/ipaserver-install.log']
  }

  # Make sure the FQDN is set in /etc/hosts to avoid any resolve
  # issue when install FreeIPA server
  host { $fqdn:
    ip           => $ipaddress,
    host_aliases => [$::hostname],
    require      => Exec['remove-hosts-entry'],
    before       => Exec['ipa-install'],
  }

  $idstart = Integer($facts['uid_max']) + 1
  $ipa_server_install_cmd = @("IPASERVERINSTALL"/L)
    /sbin/ipa-server-install \
    --setup-dns \
    --hostname ${fqdn} \
    --ds-password ${ds_password} \
    --admin-password ${admin_password} \
    --idstart=${idstart} \
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

  exec { 'ipa-install':
    command => Sensitive($ipa_server_install_cmd),
    creates => '/etc/ipa/default.conf',
    timeout => 0,
    require => [Package['ipa-server-dns']],
    notify  => Service['systemd-logind']
  }

  file { '/etc/NetworkManager/conf.d/zzz-puppet.conf':
    mode    => '0644',
    content => epp(
      'profile/freeipa/zzz-puppet.conf',
      {
        'int_domain_name' => $int_domain_name,
        'nameservers'     => ['127.0.0.1'],
      }),
    notify  => Service['NetworkManager'],
    require => Exec['ipa-install'],
  }

  file_line { 'ipa_server_fileline':
    ensure  => present,
    path    => '/etc/ipa/default.conf',
    after   => "domain = ${int_domain_name}",
    line    => "server = ${::hostname}.${int_domain_name}",
    require => Exec['ipa-install'],
  }

  exec { 'ipa_config-mod_auth-otp':
    command     => 'kinit_wrapper ipa config-mod --user-auth-type=otp',
    refreshonly => true,
    require     => [File['kinit_wrapper'],],
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-install']
  }

  # Configure the password of the admin accounts to never expire
  exec { 'ipa_admin_passwd_exp':
    command     => 'kinit_wrapper ipa pwpolicy-add --minlife=0 --maxlife=0 --priority=1 admins',
    refreshonly => true,
    require     => [File['kinit_wrapper'],],
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-install'],
  }
  ~> exec { 'ipa_admin_passwd_reset':
    command     => 'echo -e "$IPA_ADMIN_PASSWD\n$IPA_ADMIN_PASSWD\n$IPA_ADMIN_PASSWD" | kinit_wrapper kpasswd',
    refreshonly => true,
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin']
  }

  exec { 'ipa_automember_ipausers':
    command     => 'kinit_wrapper ipa automember-default-group-set --default-group=ipausers --type=group',
    refreshonly => true,
    require     => [File['kinit_wrapper'], ],
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-install']
  }

  exec { 'ipa_hostgroup_not_mgmt':
    command     => 'kinit_wrapper ipa hostgroup-add not_mgmt',
    refreshonly => true,
    require     => [File['kinit_wrapper'], Exec['ipa-install']],
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-install']
  }
  ~> exec { 'ipa_automember_not_mgmt':
    command     => 'kinit_wrapper ipa automember-add not_mgmt --type=hostgroup',
    refreshonly => true,
    require     => [File['kinit_wrapper'], Exec['ipa-install']],
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin']
  }
  ~> exec { 'ipa_automember_condition_not_mgmt':
    command     => 'kinit_wrapper ipa automember-add-condition not_mgmt --type=hostgroup --key=fqdn --inclusive-regex=.* --exclusive-regex="^mgmt.*"',
    refreshonly => true,
    require     => [File['kinit_wrapper'], Exec['ipa-install']],
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin']
  }
  ~> exec { 'ipa_automember_rebuild_hostgroup':
    command     => 'kinit_wrapper ipa automember-rebuild --type=hostgroup',
    refreshonly => true,
    require     => [File['kinit_wrapper'], Exec['ipa-install']],
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin']
  }

  exec { 'ipa_hbacrule_notmgmt':
    command     => 'kinit_wrapper ipa hbacrule-add ipauser_not_mgmt --servicecat=all',
    refreshonly => true,
    require     => [File['kinit_wrapper'],],
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-install']
  }

  exec { 'ipa_hbacrule_notmgmt_addusers':
    command     => 'kinit_wrapper ipa hbacrule-add-user ipauser_not_mgmt --groups=ipausers',
    refreshonly => true,
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    require     => [File['kinit_wrapper'],],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => [Exec['ipa_hbacrule_notmgmt'], Exec['ipa_automember_ipausers']]
  }

  exec { 'ipa_hbacrule_notmgmt_addhosts':
    command     => 'kinit_wrapper ipa hbacrule-add-host ipauser_not_mgmt --hostgroups=not_mgmt',
    refreshonly => true,
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    require     => [File['kinit_wrapper'],],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => [Exec['ipa_hbacrule_notmgmt'], Exec['ipa_hostgroup_not_mgmt']]
  }

  exec { 'ipa_add_record_CNAME':
    command     => "kinit_wrapper ipa dnsrecord-add ${int_domain_name} ipa --cname-rec ${::hostname}",
    refreshonly => true,
    require     => [File['kinit_wrapper'], ],
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-install'],
  }

  exec { 'ipa_add_host_ipa':
    command     => "kinit_wrapper ipa host-add ipa.${int_domain_name} --force",
    refreshonly => true,
    require     => [File['kinit_wrapper'], ],
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-install'],
  }

  exec { 'ipa_add_service_principal_http':
    command     => "kinit_wrapper ipa service-add-principal HTTP/${fqdn} HTTP/ipa.${int_domain_name}",
    refreshonly => true,
    require     => [
      File['kinit_wrapper'],
      Exec['ipa_add_record_CNAME'],
      Exec['ipa_add_host_ipa'],
    ],
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-install'],
  }

  exec { 'ipa_add_service_principal_ldap':
    command     => "kinit_wrapper ipa service-add-principal ldap/${fqdn} ldap/ipa.${int_domain_name}",
    refreshonly => true,
    require     => [
      File['kinit_wrapper'],
      Exec['ipa_add_record_CNAME'],
      Exec['ipa_add_host_ipa'],
    ],
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-install'],
  }

  $regen_cert_cmd = lookup('profile::freeipa::server::regen_cert_cmd')
  exec { 'ipa_regen_cert':
    command     => "${regen_cert_cmd} -D ipa.${int_domain_name}",
    refreshonly => true,
    require     => [
      Exec['ipa_add_service_principal_http'],
      Exec['ipa_add_service_principal_ldap'],
    ],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-install'],
  }

  service { 'ipa':
    ensure  => running,
    enable  => true,
    require => Exec['ipa-install'],
  }

  service { 'httpd':
    ensure  => running,
    enable  => true,
    require => Exec['ipa-install'],
  }

  file { '/etc/httpd/conf.d/ipa-rewrite.conf':
    content => epp(
      'profile/freeipa/ipa-rewrite.conf',
      {
        'referee'     => $fqdn,
        'referer'     => "ipa.${domain_name}",
        'referer_int' => "ipa.${int_domain_name}",
      }
    ),
    notify  => Service['httpd'],
    require => Exec['ipa-install'],
    seltype => 'httpd_config_t',
  }

  # Monitor change of the directory server password
  # and apply change if the current password hash does
  # not correspond to the password definned in the hieradata.
  # This is needed because the password is generated by
  # the puppet server during the bootstrap phase and it can
  # change if the puppet server is reinstalled.
  $ds_domain = upcase(regsubst($int_domain_name, '\.', '-', 'G'))
  $ds_file = "/etc/dirsrv/slapd-${ds_domain}/dse.ldif"
  $reset_ds_password_cmd = @("EOT")
    dsctl ${ds_domain} stop && \
    sed -n ':loop N; s/\n //; t loop; P; D' ${ds_file} |\
        sed "s;^nsslapd-rootpw:.*$;nsslapd-rootpw: $(pwdhash ${ds_password});g" \
        > ${ds_file}.tmp && \
    mv -f ${ds_file}.tmp ${ds_file} && \
    dsctl ${ds_domain} start
    |EOT
  $check_ds_password_cmd = "pwdhash -c $(sed -n ':loop N; s/\\n //; t loop; P; D' ${ds_file} | grep -oP 'nsslapd-rootpw: \\K(.*)') ${ds_password}"
  exec { 'reset ds password':
    command => Sensitive($reset_ds_password_cmd),
    unless  => Sensitive($check_ds_password_cmd),
    path    => ['/usr/sbin', '/usr/bin', '/bin'],
    require => Exec['ipa-install'],
  }

  $ldap_dc_string = join(split($int_domain_name, '[.]').map |$dc| { "dc=${dc}" }, ',')
  $reset_admin_password_cmd = @("EOT")
    ldappasswd -ZZ -D 'cn=Directory Manager' -w ${ds_password} \
      -S uid=admin,cn=users,cn=accounts,${ldap_dc_string} \
      -s ${admin_password} -H ldap://${fqdn}
    |EOT
  $check_admin_password_cmd = "echo ${admin_password} | kinit admin && kdestroy"
  exec { 'reset admin password':
    command => Sensitive($reset_admin_password_cmd),
    unless  => Sensitive($check_admin_password_cmd),
    path    => ['/usr/sbin', '/usr/bin', '/bin'],
    require => [
      Exec['ipa-install'],
      Exec['reset ds password'],
    ],
  }
}

class profile::freeipa::mokey(
  Integer $port,
  String $password,
  Boolean $enable_user_signup,
  Boolean $require_verify_admin,
)
{
  yumrepo { 'mokey-copr-repo':
    enabled             => true,
    descr               => 'Copr repo for mokey owned by cmdntrf',
    baseurl             => "https://download.copr.fedorainfracloud.org/results/cmdntrf/mokey/epel-\$releasever-\$basearch/",
    skip_if_unavailable => true,
    gpgcheck            => 1,
    gpgkey              => 'https://download.copr.fedorainfracloud.org/results/cmdntrf/mokey/pubkey.gpg',
    repo_gpgcheck       => 0,
  }

  package { 'mokey':
    ensure  => 'installed',
    require => [
      Yumrepo['mokey-copr-repo'],
    ],
  }

  $ipa_passwd = lookup('profile::freeipa::server::admin_password')
  $domain_name = lookup('profile::freeipa::base::domain_name')
  $int_domain_name = "int.${domain_name}"

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

  exec { 'ipa_mokey_role_add':
    command     => 'kinit_wrapper ipa role-add "Mokey User Manager" --desc="Mokey User management"',
    refreshonly => true,
    require     => [
      File['kinit_wrapper'],
    ],
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa-install'],
  }

  exec { 'ipa_mokey_role_add_privilege':
    command     => 'kinit_wrapper ipa role-add-privilege "Mokey User Manager" --privilege="User Administrators"',
    refreshonly => true,
    require     => [
      File['kinit_wrapper'],
    ],
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa_mokey_role_add'],
  }

  exec { 'ipa_mokey_user_add':
    command     => 'kinit_wrapper ipa user-add mokeyapp --first Mokey --last App',
    refreshonly => true,
    require     => [
      File['kinit_wrapper'],
    ],
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => Exec['ipa_mokey_role_add'],
  }

  exec { 'ipa_mokey_role_add_member':
    command     => 'kinit_wrapper ipa role-add-member "Mokey User Manager" --users=mokeyapp',
    refreshonly => true,
    require     => [
      File['kinit_wrapper'],
    ],
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => [
      Exec['ipa_mokey_role_add'],
      Exec['ipa_mokey_user_add'],
    ]
  }

  file { '/etc/mokey/keytab':
    ensure  => 'directory',
    seltype => 'etc_t',
    group   => 'mokey',
    mode    => '0640',
    require => Package['mokey'],
  }

  # TODO: Fix server hostname to ipa.${int_domain_name}
  exec { 'ipa_getkeytab_mokeyapp':
    command     => 'kinit_wrapper ipa-getkeytab -s $(grep -m1 -oP \'(host|server) = \K.+\' /etc/ipa/default.conf) -p mokeyapp -k /etc/mokey/keytab/mokeyapp.keytab',
    refreshonly => true,
    require     => [
      File['kinit_wrapper'],
      File['/etc/mokey/keytab']
    ],
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => [
      Exec['ipa_mokey_role_add'],
      Exec['ipa_mokey_user_add'],
    ]
  }

  file { '/etc/mokey/keytab/mokeyapp.keytab':
    group   => 'mokey',
    mode    => '0640',
    require => [
      Package['mokey'],
      Exec['ipa_mokey_user_add'],
      Exec['ipa_getkeytab_mokeyapp'],
    ]
  }

  $mokey_subdomain = lookup('profile::reverse_proxy::mokey_subdomain')
  $mokey_hostname = "${mokey_subdomain}.${domain_name}"
  file { '/etc/mokey/mokey.yaml':
    group   => 'mokey',
    mode    => '0640',
    require => [
      Package['mokey'],
    ],
    content => epp(
      'profile/freeipa/mokey.yaml',
      {
        'user'                 => 'mokey',
        'password'             => $password,
        'dbname'               => 'mokey',
        'port'                 => $port,
        'auth_key'             => seeded_rand_string(64, "${password}+auth_key", 'ABCDEF0123456789'),
        'enc_key'              => seeded_rand_string(64, "${password}+enc_key", 'ABCEDF0123456789'),
        'enable_user_signup'   => $enable_user_signup,
        'require_verify_admin' => $require_verify_admin,
        'email_link_base'      => "https://${mokey_hostname}/",
        'email_from'           => "admin@${domain_name}",
      }
    ),
  }

  service { 'mokey':
    ensure    => running,
    enable    => true,
    require   => [
      Package['mokey'],
      Exec['ipa_getkeytab_mokeyapp'],
    ],
    subscribe => [
      File['/etc/mokey/mokey.yaml'],
      Mysql::Db['mokey'],
    ]
  }
}
