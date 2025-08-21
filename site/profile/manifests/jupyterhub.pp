class profile::jupyterhub::hub (
  String $register_url = '', # lint:ignore:params_empty_string_assignment
  String $reset_pw_url = '', # lint:ignore:params_empty_string_assignment
) {
  contain jupyterhub

  Service <| tag == profile::sssd |> ~> Service['jupyterhub']
  Yumrepo['epel'] -> Class['jupyterhub']

  file { '/etc/jupyterhub/templates/login.html':
    content => epp('profile/jupyterhub/login.html', {
        'register_url' => $register_url,
        'reset_pw_url' => $reset_pw_url,
      }
    ),
  }
  include profile::slurm::submitter

  @consul::service { 'jupyterhub':
    port => 8081,
    tags => ['jupyterhub'],
  }

  file { "${jupyterhub::prefix}/bin/ipa_create_user.py":
    source  => 'puppet:///modules/profile/users/ipa_create_user.py',
    mode    => '0755',
    require => Jupyterhub::Uv::Venv['hub'],
  }

  file { "${jupyterhub::prefix}/bin/kinit_wrapper":
    source  => 'puppet:///modules/profile/freeipa/kinit_wrapper',
    mode    => '0755',
    require => Jupyterhub::Uv::Venv['hub'],
  }
}

class profile::jupyterhub::node {
  include jupyterhub::node
  if lookup('jupyterhub::kernel::install_method') == 'venv' and lookup('jupyterhub::kernel::venv::python') =~ /^\/cvmfs.*/ {
    Class['profile::software_stack'] -> Class['jupyterhub::kernel::venv']
  }
}

class profile::jupyterhub::hub::keytab {
  $ipa_domain = lookup('profile::freeipa::base::ipa_domain')
  $jupyterhub_prefix = lookup('jupyterhub::prefix', undef, undef, '/opt/jupyterhub')

  $fqdn = "${facts['networking']['hostname']}.${ipa_domain}"
  $service_name = "jupyterhub/${fqdn}"
  $service_register_script = @("EOF")
    api.Command.batch(
      { 'method': 'service_add',           'params': [['${service_name}'], {}]},
      { 'method': 'service_add_principal', 'params': [['${service_name}', 'jupyterhub/jupyterhub'], {}]},
      { 'method': 'role_add',              'params': [['JupyterHub'], {'description' : 'JupyterHub User management'}]},
      { 'method': 'role_add_privilege',    'params': [['JupyterHub'], {'privilege'   : 'Group Administrators'}]},
      { 'method': 'role_add_privilege',    'params': [['JupyterHub'], {'privilege'   : 'User Administrators'}]},
      { 'method': 'role_add_member',       'params': [['JupyterHub'], {'service'     : '${service_name}'}]},
    )
    |EOF

  file { "${jupyterhub_prefix}/bin/ipa_register_service.py":
    content => $service_register_script,
    require => Jupyterhub::Uv::Venv['hub'],
  }

  $ipa_passwd = lookup('profile::freeipa::server::admin_password')
  $keytab_command = @("EOT")
    kinit_wrapper ipa console ${jupyterhub_prefix}/bin/ipa_register_service.py && \
    kinit_wrapper ipa-getkeytab -p jupyterhub/jupyterhub -k /etc/jupyterhub/jupyterhub.keytab
    |EOT
  exec { 'jupyterhub_keytab':
    command     => $keytab_command,
    creates     => '/etc/jupyterhub/jupyterhub.keytab',
    require     => [
      File['/etc/jupyterhub'],
      File["${jupyterhub_prefix}/bin/kinit_wrapper"],
      Exec['ipa-install'],
    ],
    subscribe   => File["${jupyterhub_prefix}/bin/ipa_register_service.py"],
    environment => ["IPA_ADMIN_PASSWD=${ipa_passwd}"],
    path        => ['/bin', '/usr/bin', '/sbin','/usr/sbin', "${jupyterhub_prefix}/bin"],
  }

  file { '/etc/jupyterhub/jupyterhub.keytab':
    owner     => 'root',
    group     => 'jupyterhub',
    mode      => '0640',
    subscribe => Exec['jupyterhub_keytab'],
    require   => Group['jupyterhub'],
  }
}
