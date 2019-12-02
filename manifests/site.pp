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
  include jupyterhub
  include profile::reverse_proxy
  include profile::nfs::client
  include profile::freeipa::client
}

node /^mgmt1$/ {
  class { [
    'profile::consul::server',
    'profile::metrics::exporter'
    ]:
    stage => 'first'
  }

  class { [
    'profile::freeipa::server',
    'profile::nfs::server',
    ]:
    stage => 'second'
  }

  include profile::metrics::server
  include profile::rsyslog::server
  include profile::squid::server
  include profile::slurm::controller

  include profile::base
  include profile::freeipa::guest_accounts
  include profile::slurm::accounting
}

node /^mgmt(?:[2-9]|[1-9]\d\d*)$/ {
  include profile::consul::client
  include profile::base
  include profile::rsyslog::client
  include profile::freeipa::client
  include profile::metrics::exporter
}

node /^node\d+$/ {
  include profile::consul::client
  include profile::base
  include profile::metrics::exporter
  include profile::rsyslog::client
  include profile::cvmfs::client
  include profile::gpu
  include profile::singularity
  include jupyterhub::node

  include profile::nfs::client
  include profile::slurm::node
  include profile::freeipa::client
}
