class profile::jupyterhub::hub {
  contain jupyterhub
  Yumrepo['epel'] -> Class['jupyterhub']

  $enable_user_signup = lookup('profile::freeipa::mokey::enable_user_signup')
  $domain_name = lookup('profile::freeipa::base::domain_name')
  $mokey_subdomain = lookup('profile::reverse_proxy::mokey_subdomain')
  $mokey_hostname = "${mokey_subdomain}.${domain_name}"

  file { '/etc/jupyterhub/templates/login.html':
    ensure  => present,
    content => epp('profile/jupyterhub/login.html', {
        'mokey_hostname'     => $mokey_hostname,
        'enable_user_signup' => $enable_user_signup,
      }
    ),
  }
}

class profile::jupyterhub::node {
  if lookup('jupyterhub::node::prefix', String, undef, '') !~ /^\/cvmfs.*/ {
    include jupyterhub::node
    if lookup('jupyterhub::kernel::setup') == 'venv' {
      Class['profile::cvmfs::client'] -> Class['jupyterhub::kernel::venv']
    }
  }
}
