node default {
  require profile::base
  require profile::freeipa::client
  include profile::nfs::client
  include profile::cvmfs::client
  include profile::rsyslog::client
  include profile::slurm::submitter
  include jupyterhub
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

node /^mgmt\d+$/ {
  require profile::base
  require profile::freeipa::server
  include profile::freeipa::guest_accounts
  include profile::nfs::server
  include profile::rsyslog::server
  include profile::squid::server
  include profile::slurm::controller
}

node /^node\d+$/ {
  include profile::base
  include profile::freeipa::client
  include profile::nfs::client
  include profile::rsyslog::client
  include profile::cvmfs::client
  include profile::gpu
  include profile::slurm::node

  Class['profile::freeipa::client'] -> Class['profile::nfs::client'] -> Class['profile::slurm::node']
}
