node default {
  include profile::base
  include profile::freeipa::client
  include profile::nfs::client
  include profile::cvmfs::client
  include profile::rsyslog::client
  include profile::slurm::submitter
  include profile::globus::base
  include jupyterhub

}

node /^login\d+$/ {
  include profile::base
  include profile::freeipa::client
  include profile::nfs::client
  include profile::cvmfs::client
  include profile::rsyslog::client
  include profile::slurm::submitter
  include profile::globus::base
  include jupyterhub
}

node /^mgmt\d+$/ {
  stage { 'first': }
  # include profile::freeipa::server
  class { 'profile::freeipa::server':
    stage => 'first'
  }
  include profile::base
  include profile::freeipa::guest_accounts
  include profile::nfs::server
  include profile::rsyslog::server
  include profile::squid::server
  include profile::slurm::controller
  include profile::slurm::accounting

  Stage['first'] -> Stage['main']
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
