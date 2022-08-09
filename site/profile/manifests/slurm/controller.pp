# Slurm controller class. This where slurmctld is ran.
# @param selinux_context
class profile::slurm::controller (
  String $selinux_context = 'user_u:user_r:user_t:s0',
) {
  contain profile::slurm::base
  include profile::mail::server

  file { '/usr/sbin/slurm_mail':
    source => 'puppet:///modules/profile/slurm/slurm_mail',
    mode   => '0755',
  }

  $slurm_version = lookup('profile::slurm::base::slurm_version')
  if $slurm_version == '21.08' {
    file { '/etc/slurm/job_submit.lua':
      owner   => 'slurm',
      group   => 'slurm',
      content => epp('profile/slurm/job_submit.lua',
        {
          'selinux_context' => $selinux_context,
        }
      ),
    }
  }

  consul::service { 'slurmctld':
    port    => 6817,
    require => Tcp_conn_validator['consul'],
    token   => lookup('profile::consul::acl_api_token'),
  }

  package { 'slurm-slurmctld':
    ensure  => 'installed',
    require => Package['munge'],
  }

  consul_template::watch { 'slurm.conf':
    require     => File['/etc/slurm/slurm.conf.tpl'],
    config_hash => {
      perms       => '0644',
      source      => '/etc/slurm/slurm.conf.tpl',
      destination => '/etc/slurm/slurm.conf',
      command     => 'systemctl restart slurmctld || true',
    },
  }

  consul_template::watch { 'node.conf':
    require     => File['/etc/slurm/node.conf.tpl'],
    config_hash => {
      perms       => '0644',
      source      => '/etc/slurm/node.conf.tpl',
      destination => '/etc/slurm/node.conf',
      command     => 'systemctl restart slurmctld || true',
    },
  }

  service { 'slurmctld':
    ensure  => 'running',
    enable  => true,
    require => [
      Package['slurm-slurmctld'],
      Wait_for['slurmctldhost_set'],
    ],
  }

  logrotate::rule { 'slurmctld':
    path         => '/var/log/slurm/slurmctld.log',
    rotate       => 5,
    ifempty      => false,
    copytruncate => false,
    olddir       => false,
    size         => '5M',
    compress     => true,
    create       => true,
    create_mode  => '0600',
    create_owner => 'slurm',
    create_group => 'slurm',
    postrotate   => '/usr/bin/pkill -x --signal SIGUSR2 slurmctld',
  }
}
