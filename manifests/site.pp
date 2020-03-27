stage { ['first', 'second'] : }
Stage['first'] -> Stage['second'] -> Stage['main']

node default {
  include profile::consul::client
  include profile::base
  include profile::rsyslog::client
  include profile::freeipa::client
  include profile::metrics::exporter
}

node /^login\d+$/ {
  include profile::consul::client
  include profile::base
  include profile::metrics::exporter
  include profile::fail2ban
  include profile::cvmfs::client
  include profile::rsyslog::client
  include profile::slurm::submitter
  include profile::globus::base
  include profile::singularity
  include profile::jupyterhub::hub
  include profile::reverse_proxy
  include profile::nfs::client
  include profile::freeipa::client
}

node /^mgmt1$/ {
  include profile::consul::server
  include profile::metrics::exporter
  include profile::freeipa::server
  include profile::nfs::server

  include profile::metrics::server
  include profile::rsyslog::server
  include profile::squid::server
  include profile::slurm::controller

  include profile::base
  include profile::freeipa::guest_accounts
  include profile::slurm::accounting
  include profile::workshop::mgmt
}

node /^mgmt(?:[2-9]|[1-9]\d\d*)$/ {
  include profile::consul::client
  include profile::slurm::controller
  include profile::base
  include profile::rsyslog::client
  include profile::freeipa::client
  include profile::metrics::exporter
}

node /^[a-z0-9-]*node\d+$/ {
  include profile::consul::client
  include profile::base
  include profile::metrics::exporter
  include profile::rsyslog::client
  include profile::cvmfs::client
  include profile::gpu
  include profile::singularity
  include profile::jupyterhub::node

  include profile::nfs::client
  include profile::slurm::node
  include profile::freeipa::client
}
