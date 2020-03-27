class profile::jupyterhub::hub {
  include jupyterhub
}

class profile::jupyterhub::node {
  include jupyterhub::node
  Class['profile::cvmfs::client'] -> Class['jupyterhub::kernel::venv']
}
