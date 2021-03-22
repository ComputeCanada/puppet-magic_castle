stage { ['first', 'second'] : }
Stage['first'] -> Stage['second'] -> Stage['main']

node puppet {
  include profile::consul::server
}

node default {
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
  include profile::mfa::login
}

node /^mgmt1$/ {
  include profile::consul::client
  include profile::metrics::exporter
  include profile::freeipa::server
  include profile::base
  include profile::nfs::server

  include profile::metrics::server
  include profile::rsyslog::server
  include profile::squid::server
  include profile::slurm::controller

  include profile::freeipa::mokey
  include profile::slurm::accounting
  include profile::workshop::mgmt
  include profile::mfa::mgmt

  include profile::accounts
  include profile::accounts::guests
}

node /^mgmt(?:[2-9]|[1-9]\d\d*)$/ {
  include profile::consul::client
  include profile::slurm::controller
  include profile::base
  include profile::rsyslog::client
  include profile::freeipa::client
  include profile::metrics::exporter
  include profile::mfa::mgmt
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
  include profile::mfa::node

}
