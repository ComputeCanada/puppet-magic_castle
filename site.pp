node default {
  include profile::base
  include profile::nfs::client
  include profile::rsyslog::client
}

node /^mgmt\d+$/ {
  require profile::base
  require freeipa::server
  include profile::nfs::server
  include profile::rsyslog::server
  include profile::squid::server
  include freeipa::guest_accounts
  include slurm::controller
}

node /^login\d+$/ {
  require profile::base
  require freeipa::client
  include profile::nfs::client
  include profile::cvmfs::client
  include profile::rsyslog::client
  include jupyterhub
}

node /^node\d+$/ {
  require profile::base
  require freeipa::client
  require profile::nfs::client
  include profile::rsyslog::client
  include profile::cvmfs::client
  include profile::gpu
  include slurm::node
}
