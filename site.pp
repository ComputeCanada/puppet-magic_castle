node default {
  include profile::base
  include profile::nfs::client
  include profile::rsyslog::client
}

node /^mgmt\d+$/ {
  require profile::base
  require profile::freeipa::server
  include profile::freeipa::guest_accounts
  include profile::nfs::server
  include profile::rsyslog::server
  include profile::squid::server
  include profile::slurm::controller
}

node /^login\d+$/ {
  require profile::base
  require profile::freeipa::client
  include profile::nfs::client
  include profile::cvmfs::client
  include profile::rsyslog::client
  include profile::slurm::submitter
  include jupyterhub
}

node /^node\d+$/ {
  require profile::base
  require profile::freeipa::client
  require profile::nfs::client
  include profile::rsyslog::client
  include profile::cvmfs::client
  include profile::gpu
  include profile::slurm::node
}
