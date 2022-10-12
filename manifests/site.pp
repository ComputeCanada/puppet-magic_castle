stage { ['first', 'second'] : }
Stage['first'] -> Stage['second'] -> Stage['main']

node default {
  $instance_tags = lookup("terraform.instances.${::hostname}.tags")

  if 'puppet' in $instance_tags {
    include profile::consul::server
  } else {
    include profile::consul::client
  }

  include profile::base
  include profile::users::local
  include profile::metrics::node_exporter

  if 'login' in $instance_tags {
    include profile::fail2ban
    include profile::cvmfs::client
    include profile::slurm::submitter
    include profile::singularity
  }

  if 'mgmt' in $instance_tags {
    include profile::freeipa::server

    include profile::metrics::server
    include profile::metrics::slurm_exporter
    include profile::userportal::server
    include profile::rsyslog::server
    include profile::squid::server
    include profile::slurm::controller

    include profile::freeipa::mokey
    include profile::slurm::accounting

    include profile::accounts
    include profile::users::ldap
    class { 'profile::sssd::client':
      domains     => lookup('profile::sssd::client::domains', undef, undef, {}),
      deny_access => true,
    }
  } else {
    include profile::freeipa::client
    include profile::sssd::client
    include profile::rsyslog::client
  }

  if 'node' in $instance_tags {
    include profile::cvmfs::client
    include profile::gpu
    include profile::singularity
    include profile::jupyterhub::node

    include profile::slurm::node

    include profile::metrics::slurm_job_exporter

    Class['profile::nfs::client'] -> Service['slurmd']
    Class['profile::gpu'] -> Service['slurmd']
  }

  if 'nfs' in $instance_tags {
    include profile::nfs::server
  } else {
    include profile::nfs::client
  }

  if 'proxy' in $instance_tags {
    include profile::jupyterhub::hub
    include profile::reverse_proxy
  }

  if 'dtn' in $instance_tags {
    include profile::globus
  }

  if 'mfa' in $instance_tags {
    include profile::mfa
  }
}
