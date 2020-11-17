class profile::jupyterhub::hub {
  contain jupyterhub
  Yumrepo['epel'] -> Class['jupyterhub']

  $enable_user_signup = lookup('profile::freeipa::mokey::enable_user_signup')
  if $enable_user_signup {
    $ensure_login_template = 'present'
  }
  else {
    $ensure_login_template = 'absent'
  }

  $domain_name = lookup('profile::freeipa::base::domain_name')
  $mokey_subdomain = lookup('profile::reverse_proxy::mokey_subdomain')
  $mokey_hostname = "${mokey_subdomain}.${domain_name}"

  file { '/etc/jupyterhub/templates/login.html':
    ensure  => $ensure_login_template,
    content => epp('profile/jupyterhub/login.html', {
        'mokey_hostname' => $mokey_hostname,
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
