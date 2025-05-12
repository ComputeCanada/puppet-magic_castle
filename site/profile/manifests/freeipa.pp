class profile::freeipa {
  $server_ip = lookup('profile::freeipa::client::server_ip')
  $ipaddress = lookup('terraform.self.local_ip')

  if $ipaddress == $server_ip {
    include profile::freeipa::server
  } else {
    include profile::freeipa::client
  }
}

class profile::freeipa::base (String $ipa_domain) {
  if versioncmp($::facts['os']['release']['major'], '8') == 0 {
    exec { 'enable_idm:DL1':
      command => 'yum module enable -y idm:DL1',
      creates => '/etc/dnf/modules.d/idm.module',
      path    => ['/usr/bin', '/usr/sbin'],
    }
  }

  package { 'systemd':
    ensure => 'latest',
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
    enable => true,
  }

  file { '/etc/rsyslog.d/ignore-systemd-session-slice.conf':
    source => 'puppet:///modules/profile/freeipa/ignore-systemd-session-slice.conf',
    mode   => '0644',
  }
}

class profile::freeipa::client (String $server_ip) {
  include profile::freeipa::base
  include profile::sssd::client

  $ipa_domain = lookup('profile::freeipa::base::ipa_domain')
  $admin_password = lookup('profile::freeipa::server::admin_password')
  $fqdn = "${facts['networking']['hostname']}.${ipa_domain}"
  $realm = upcase($ipa_domain)
  $ipaddress = lookup('terraform.self.local_ip')

  file { '/etc/NetworkManager/conf.d/zzz-puppet.conf':
    mode    => '0644',
    content => epp('profile/freeipa/zzz-puppet.conf',
      {
        'int_domain_name' => $ipa_domain,
        'nameservers'     => union([$server_ip], $facts['nameservers']),
      }
    ),
    notify  => Service['NetworkManager'],
  }

  package { 'ipa-client':
    ensure => 'installed',
  }

  wait_for { 'ipa_https':
    query             => "openssl s_client -showcerts -connect ipa:443 </dev/null 2> /dev/null | openssl x509 -noout -text | grep --quiet DNS:ipa.${ipa_domain}",
    exit_code         => 0,
    polling_frequency => 5,
    max_retries       => 120,
    refreshonly       => true,
    subscribe         => [
      Package['ipa-client'],
      Exec['ipa-client-uninstall_bad-hostname'],
      Exec['ipa-client-uninstall_bad-server'],
    ],
  }

  # Make sure heavy lifting operations are done before waiting on mgmt1
  Package <| |> -> Wait_for['ipa_https']
  Selinux::Module <| |> -> Wait_for['ipa_https']
  Selinux::Boolean <| |> -> Wait_for['ipa_https']
  Selinux::Exec_restorecon <| |> -> Wait_for['ipa_https']

  if length($fqdn) > 63 {
    fail("The fully qualified domain name of ${fqdn} is longer than 63 characters which is not authorized by FreeIPA. Rename the host.")
  }

  exec { 'set_hostname':
    command => "/bin/hostnamectl set-hostname ${fqdn}",
    unless  => "/usr/bin/test `hostname` = ${fqdn}",
  }

  file { '/sbin/mc-ipa-client-install':
    mode   => '0755',
    source => 'puppet:///modules/profile/freeipa/mc-ipa-client-install',
  }

  $ipa_client_install_cmd = @("IPACLIENTINSTALL"/L)
    /sbin/mc-ipa-client-install \
    --domain ${ipa_domain} \
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
      Wait_for['ipa_https'],
      Augeas['sssd.conf'],
    ],
    creates   => '/etc/ipa/default.conf',
    notify    => [
      Service['systemd-logind'],
      Service['sssd'],
    ],
  }

  file_line { 'ssh_known_hosts':
    ensure    => present,
    path      => '/etc/ssh/ssh_config.d/04-ipa.conf',
    match     => '^GlobalKnownHostsFile',
    line      => 'GlobalKnownHostsFile /var/lib/sss/pubconf/known_hosts /etc/ssh/ssh_known_hosts',
    subscribe => Exec['ipa-install'],
  }

  # Configure default login selinux mapping
  exec { 'selinux_login_default':
    command => 'semanage login -m -S targeted -s "user_u" -r s0 __default__',
    unless  => 'grep -q "__default__:user_u:s0" /etc/selinux/targeted/seusers',
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    require => Exec['ipa-install'],
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
      'curl --silent $(grep -oP "xmlrpc_uri = \K(.*)" /etc/ipa/default.conf) > /dev/null; test $? -eq 35',
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
  augeas { 'selinux_provider':
    lens    => 'sssd.lns',
    incl    => '/etc/sssd/sssd.conf',
    changes => [
      "set target[ . = 'domain/${ipa_domain}']/selinux_provider none",
    ],
    require => Exec['ipa-install'],
    notify  => Service['sssd'],
  }
}

class profile::freeipa::server (
  Integer $id_start,
  String $admin_password,
  String $ds_password,
  Array[String] $hbac_services = ['sshd', 'jupyterhub-login'],
  Boolean $enable_mokey = true,
) {
  include profile::base::etc_hosts
  include profile::freeipa::base
  include profile::sssd::client
  include profile::users::ldap

  if $enable_mokey {
    include profile::freeipa::mokey
  }

  file { 'kinit_wrapper':
    path   => '/usr/bin/kinit_wrapper',
    source => 'puppet:///modules/profile/freeipa/kinit_wrapper',
    mode   => '0755',
  }

  $proxy_domain = lookup('profile::reverse_proxy::domain_name')
  $ipa_domain = lookup('profile::freeipa::base::ipa_domain')

  package { 'ipa-server-dns':
    ensure => 'installed',
  }

  if versioncmp($::facts['os']['release']['major'], '8') == 0 {
    # Fix FreeIPA issue adding 2 minutes of wait time for nothing
    # https://pagure.io/freeipa/issue/9358
    # TODO: remove this patch once FreeIPA >= 4.10 is made available
    # in RHEL 8.
    ensure_packages(['patch'], { ensure => 'present' })
    $python_version = lookup('os::redhat::python3::version')
    file { 'freeipa_27e9181bdc.patch':
      path   => "/usr/lib/python${python_version}/site-packages/freeipa_27e9181bdc.patch",
      source => 'puppet:///modules/profile/freeipa/27e9181bdc684915a7f9f15631f4c3dd6ac5f884.patch',
    }
    exec { 'patch -p1 -r - --forward --quiet < freeipa_27e9181bdc.patch':
      cwd         => "/usr/lib/python${python_version}/site-packages",
      path        => ['/usr/bin', '/bin'],
      subscribe   => [
        File['freeipa_27e9181bdc.patch'],
        Package['ipa-server-dns'],
      ],
      refreshonly => true,
      before      => Exec['ipa-install'],
      returns     => [0, 1],
    }
  }

  $realm = upcase($ipa_domain)
  $fqdn = "${facts['networking']['hostname']}.${ipa_domain}"
  $reverse_zone = profile::getreversezone()
  $ipaddress = lookup('terraform.self.local_ip')

  $ipa_server_install_cmd = @("IPASERVERINSTALL"/L)
    /sbin/ipa-server-install \
    --setup-dns \
    --hostname ${fqdn} \
    --ds-password ${ds_password} \
    --admin-password ${admin_password} \
    --idstart=${id_start} \
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
    --domain=${ipa_domain} \
    --no_hbac_allow
    | IPASERVERINSTALL

  exec { 'ipa-install':
    command => Sensitive($ipa_server_install_cmd),
    creates => '/etc/ipa/default.conf',
    timeout => 0,
    require => [
      Package['ipa-server-dns'],
      File['/etc/hosts'],
    ],
    notify  => [
      Service['systemd-logind'],
      Service['sssd'],
    ],
  }

  file { '/etc/NetworkManager/conf.d/zzz-puppet.conf':
    mode    => '0644',
    content => epp('profile/freeipa/zzz-puppet.conf',
      {
        'int_domain_name' => $ipa_domain,
        'nameservers'     => ['127.0.0.1'],
      }
    ),
    notify  => Service['NetworkManager'],
    require => Exec['ipa-install'],
  }

  file_line { 'ipa_server_fileline':
    ensure  => present,
    path    => '/etc/ipa/default.conf',
    after   => "domain = ${ipa_domain}",
    line    => "server = ${fqdn}",
    require => Exec['ipa-install'],
  }

  $ipa_server_base_config = @("EOF")
    api.Command.batch(
      { 'method': 'config_mod', 'params': [[], {'ipauserauthtype': 'otp'}]},
      { 'method': 'config_mod', 'params': [[], {'ipadefaultloginshell': '/bin/bash'}]},
      { 'method': 'pwpolicy_add', 'params': [['admins'], {'krbminpwdlife': 0, 'krbmaxpwdlife': 0, 'cospriority': 1}]},
      { 'method': 'dnsrecord_add', 'params': [['${ipa_domain}', 'ipa'], {'cnamerecord': '${facts['networking']['hostname']}'}]},
      { 'method': 'host_add', 'params': [['ipa.${ipa_domain}'], {'force': True}]},
      { 'method': 'service_add_principal', 'params': [['HTTP/${fqdn}', 'HTTP/ipa.${ipa_domain}'], {}]},
      { 'method': 'service_add_principal', 'params': [['ldap/${fqdn}', 'ldap/ipa.${ipa_domain}'], {}]},
    )
    |EOF

  file { '/etc/ipa/ipa_server_base_config.py':
    content => $ipa_server_base_config,
    require => Exec['ipa-install'],
  }

  exec { 'ipa_server_base_config':
    command     => 'kinit_wrapper ipa console /etc/ipa/ipa_server_base_config.py',
    refreshonly => true,
    require     => [
      File['/etc/ipa/ipa_server_base_config.py'],
      Exec['ipa-install'],
    ],
    subscribe   => File['/etc/ipa/ipa_server_base_config.py'],
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
  }

  # Configure the password of the admin accounts to never expire
  ~> exec { 'ipa_admin_passwd_reset':
    command     => 'echo -e "$IPA_ADMIN_PASSWD\n$IPA_ADMIN_PASSWD\n$IPA_ADMIN_PASSWD" | kinit_wrapper kpasswd',
    refreshonly => true,
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
  }

  $regen_cert_cmd = 'ipa-getcert list | grep -oP "Request ID \'\K[^\']+" | xargs -I \'{}\' ipa-getcert resubmit -i \'{}\' -w'
  exec { 'ipa_regen_cert':
    command   => "${regen_cert_cmd} -D ipa.${ipa_domain}",
    path      => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    unless    => ['ipa-getcert list | grep -oPq  \'dns:.*[\ ,]ipa\.int\..*\''],
    tries     => 5,
    try_sleep => 10,
    require   => [
      Exec['ipa_server_base_config'],
      Exec['ipa-install'],
    ],
  }

  $instances = lookup('terraform.instances')
  $tags = unique(flatten($instances.map |$key, $values| { $values['tags'] }))
  $prefixes_tags = Hash(unique($instances.map |$key, $values| { [$values['prefix'], $values['tags']] }))
  file { '/etc/ipa/hbac_rules.py':
    mode    => '0700',
    content => epp(
      'profile/freeipa/hbac_rules.py',
      {
        'tags'          => $tags,
        'prefixes_tags' => $prefixes_tags,
        'ipa_domain'    => $ipa_domain,
        'hbac_services' => $hbac_services,
      }
    ),
  }

  exec { 'hbac_rules':
    command     => 'kinit_wrapper ipa console /etc/ipa/hbac_rules.py',
    refreshonly => true,
    require     => [
      File['kinit_wrapper'],
    ],
    environment => ["IPA_ADMIN_PASSWD=${admin_password}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => [
      File['/etc/ipa/hbac_rules.py'],
      Exec['ipa-install'],
    ],
  }

  service { 'ipa':
    ensure  => running,
    enable  => true,
    require => Exec['ipa-install'],
  }

  service { 'httpd':
    ensure  => running,
    enable  => true,
    restart => '/usr/bin/systemctl reload httpd',
    require => Exec['ipa-install'],
  }

  file { '/etc/httpd/conf.d/ipa-rewrite.conf':
    content => epp(
      'profile/freeipa/ipa-rewrite.conf',
      {
        'referee'           => $fqdn,
        'external_hostname' => "ipa.${proxy_domain}",
        'internal_hostname' => "ipa.${ipa_domain}",
      }
    ),
    notify  => Service['httpd'],
    require => Exec['ipa-install'],
    seltype => 'httpd_config_t',
  }

  $server_status = @(EOF)
    <Location /server-status>
      SetHandler server-status
      Require local
    </Location>
    |EOF
  @file { '/etc/httpd/conf.d/server-status.conf':
    content => $server_status,
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
  $ds_domain = upcase(regsubst($ipa_domain, '\.', '-', 'G'))
  $ds_file = "/etc/dirsrv/slapd-${ds_domain}/dse.ldif"
  $reset_ds_password_cmd = @("EOT")
    dsctl ${ds_domain} stop && \
    sed -n ':loop N; s/\n //; t loop; P; D' ${ds_file} |\
        sed "s;^nsslapd-rootpw:.*$;nsslapd-rootpw: $(pwdhash ${ds_password});g" \
        > ${ds_file}.tmp && \
    mv -f ${ds_file}.tmp ${ds_file} && \
    dsctl ${ds_domain} start
    |EOT
  $check_ds_password_cmd = "pwdhash -c $(sed -n ':loop N; s/\\n //; t loop; P; D' ${ds_file} | grep -oP 'nsslapd-rootpw: \\K(.*)') ${ds_password}" # lint:ignore:140chars
  exec { 'reset ds password':
    command => Sensitive($reset_ds_password_cmd),
    unless  => Sensitive($check_ds_password_cmd),
    path    => ['/usr/sbin', '/usr/bin', '/bin'],
    require => Exec['ipa-install'],
  }

  $ldap_dc_string = join(split($ipa_domain, '[.]').map |$dc| { "dc=${dc}" }, ',')
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

  Service <| tag == 'profile::accounts' and title == 'mkhome' |>
  Service <| tag == 'profile::accounts' and title == 'mkproject' |>
}

class profile::freeipa::mokey (
  Integer $port,
  String $password,
  Boolean $enable_user_signup,
  Boolean $require_verify_admin,
  Array[String] $access_tags,
) {
  include mysql::server

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
  $ipa_domain = lookup('profile::freeipa::base::ipa_domain')

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

  $fqdn = "${facts['networking']['hostname']}.${ipa_domain}"
  $service_name = "mokey/${fqdn}"
  $service_register_script = @("EOF")
    api.Command.batch(
      { 'method': 'service_add',           'params': [['${service_name}'], {}]},
      { 'method': 'service_add_principal', 'params': [['${service_name}', 'mokey/mokey'], {}]},
      { 'method': 'role_add',              'params': [['MokeyApp'], {'description' : 'Mokey User management'}]},
      { 'method': 'role_add_privilege',    'params': [['MokeyApp'], {'privilege'   : 'User Administrators'}]},
      { 'method': 'role_add_member',       'params': [['MokeyApp'], {'service'     : '${service_name}'}]},
    )
    |EOF

  file { '/etc/mokey/mokey_ipa_service_register.py':
    content => $service_register_script,
    require => [
      Package['mokey'],
    ],
  }

  exec { 'mokey_ipa_service_register':
    command     => 'kinit_wrapper ipa console /etc/mokey/mokey_ipa_service_register.py',
    refreshonly => true,
    require     => [
      File['kinit_wrapper'],
      Exec['ipa-install'],
    ],
    subscribe   => File['/etc/mokey/mokey_ipa_service_register.py'],
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
  }

  file { '/etc/mokey/keytab':
    ensure  => 'directory',
    seltype => 'etc_t',
    group   => 'mokey',
    mode    => '0640',
    require => Package['mokey'],
  }

  exec { 'ipa_getkeytab_mokeyapp':
    command     => 'kinit_wrapper ipa-getkeytab -p mokey/mokey -k /etc/mokey/keytab/mokeyapp.keytab', # lint:ignore:140chars
    creates     => '/etc/mokey/keytab/mokeyapp.keytab',
    require     => [
      File['kinit_wrapper'],
      File['/etc/mokey/keytab']
    ],
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    subscribe   => [
      Exec['mokey_ipa_service_register'],
    ],
  }

  file { '/etc/mokey/keytab/mokeyapp.keytab':
    group   => 'mokey',
    mode    => '0640',
    require => [
      Package['mokey'],
      Exec['mokey_ipa_service_register'],
    ],
  }

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
        'email_link_base'      => "https://${lookup('terraform.data.domain_name')}/",
        'email_from'           => "admin@${lookup('terraform.data.domain_name')}",
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
    ],
  }

  exec { 'ipa_group_self-signup':
    command     => 'kinit_wrapper ipa group-add self-signup --nonposix',
    refreshonly => true,
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    require     => [File['kinit_wrapper'],],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    returns     => [0],
    subscribe   => [
      Package['mokey'],
      Exec['ipa-install'],
    ],
  }

  exec { 'ipa_self-signup_automember':
    command     => 'kinit_wrapper ipa automember-add --type=group self-signup',
    refreshonly => true,
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    require     => [File['kinit_wrapper'],],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    returns     => [0],
    subscribe   => [
      Exec['ipa_group_self-signup']
    ],
  }

  # Users self signing with Mokey have to provide a valid email address.
  # Users created with ipa-create-user.py script are assigned an internal email address
  # which domain corresponds to the internal domain name. We therefore create a rule
  # for which every user with a non empty email address that is not internal should be
  # part of the self-signup group.
  # We had to come up with this automember rule because Mokey does not provide the ability
  # to assign a group to users who self-signup.
  exec { 'ipa_self-signup_automember-rule':
    command     => "kinit_wrapper ipa automember-add-condition self-signup --type=group --key=mail --inclusive-regex=\'^(?!\s*$).+\' --exclusive-regex=\'@${ipa_domain}$\'",
    refreshonly => true,
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    require     => [File['kinit_wrapper'],],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    returns     => [0],
    subscribe   => [
      Exec['ipa_self-signup_automember'],
    ],
  }

  $access_tags.each |$tag| {
    exec { "ipa_hbacrule_self-signup_${tag}":
      command     => "kinit_wrapper ipa hbacrule-add-user ${tag} --groups=self-signup",
      refreshonly => true,
      environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
      require     => [File['kinit_wrapper'],],
      path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
      returns     => [0, 1, 2],
      subscribe   => [
        Exec['ipa_group_self-signup'],
        Exec['hbac_rules'],
      ],
    }
  }
}
