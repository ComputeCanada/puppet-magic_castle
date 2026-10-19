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
    require => Uv::Venv['hub'],
  }

  file { "${jupyterhub::prefix}/bin/kinit_wrapper":
    source  => 'puppet:///modules/profile/freeipa/kinit_wrapper',
    mode    => '0755',
    require => Uv::Venv['hub'],
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

  profile::freeipa::service_keytab { 'jupyterhub':
    service_name     => "jupyterhub/${fqdn}",
    aliases          => ['jupyterhub/jupyterhub'],
    keytab_principal => 'jupyterhub/jupyterhub',
    config_path      => "${jupyterhub_prefix}/bin/ipa_register_service.json",
    keytab_path      => '/etc/jupyterhub/jupyterhub.keytab',
    wrapper_path     => "${jupyterhub_prefix}/bin/kinit_wrapper",
    group            => 'jupyterhub',
    role_name        => 'JupyterHub',
    role_description => 'JupyterHub User management',
    privileges       => ['Group Administrators', 'User Administrators'],
    require          => [
      Uv::Venv['hub'],
      File['/etc/jupyterhub'],
      Group['jupyterhub'],
    ],
  }
}
