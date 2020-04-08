class profile::jupyterhub::hub {
  include jupyterhub
}

class profile::jupyterhub::node {
  if lookup('jupyterhub::node::prefix') !~ /^\/cvmfs.*/ {
    include jupyterhub::node
    if lookup('jupyterhub::kernel::setup') == 'venv' {
      Class['profile::cvmfs::client'] -> Class['jupyterhub::kernel::venv']
    }
  }
}
