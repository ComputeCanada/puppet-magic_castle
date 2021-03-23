stage { ['first', 'second'] : }
Stage['first'] -> Stage['second'] -> Stage['main']

node default {
  $instance_tags = $::facts['terraform']['instances'][$::hostname]['tags']

  if 'puppet' in $instance_tags {
    include profile::consul::server
  } else {
    include profile::consul::client
  }

  include profile::base
  include profile::metrics::exporter

  if 'login' in $instance_tags {
    include profile::fail2ban
    include profile::cvmfs::client
    include profile::slurm::submitter
    include profile::singularity
    include profile::mfa::login
  }

  if 'mgmt' in $instance_tags {
    include profile::freeipa::server

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
  } else {
    include profile::freeipa::client
    include profile::rsyslog::client
  }

  if 'node' in $instance_tags {
    include profile::cvmfs::client
    include profile::gpu
    include profile::singularity
    include profile::jupyterhub::node

    include profile::slurm::node
    include profile::mfa::node
  }

  if 'nfs' in $instance_tags {
    include profile::nfs::server
  } else {
    include profile::nfs::client
  }

  if 'proxy' in $instance_tags {
    include profile::jupyterhub::hub
    include profile::reverse_proxy
    include profile::globus::base
  }
}
