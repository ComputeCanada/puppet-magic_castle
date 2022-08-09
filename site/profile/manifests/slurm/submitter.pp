# Slurm submitter class. This is for instances that neither run slurmd
# and slurmctld but still need to be able to communicate with the slurm
# controller through Slurm command-line tools.
class profile::slurm::submitter {
  contain profile::slurm::base

  consul_template::watch { 'slurm.conf':
    require     => File['/etc/slurm/slurm.conf.tpl'],
    config_hash => {
      perms       => '0644',
      source      => '/etc/slurm/slurm.conf.tpl',
      destination => '/etc/slurm/slurm.conf',
      command     => '/bin/true',
    },
  }
  consul_template::watch { 'node.conf':
    require     => File['/etc/slurm/node.conf.tpl'],
    config_hash => {
      perms       => '0644',
      source      => '/etc/slurm/node.conf.tpl',
      destination => '/etc/slurm/node.conf',
      command     => '/bin/true',
    },
  }
}
