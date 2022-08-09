# Slurm node class. This is where slurmd is ran.
class profile::slurm::node {
  contain profile::slurm::base

  yumrepo { 'spank-cc-tmpfs_mounts-copr-repo':
    enabled             => true,
    descr               => 'Copr repo for spank-cc-tmpfs_mounts owned by cmdntrf',
    baseurl             => "https://download.copr.fedorainfracloud.org/results/cmdntrf/spank-cc-tmpfs_mounts/epel-\$releasever-\$basearch/",
    skip_if_unavailable => true,
    gpgcheck            => 1,
    gpgkey              => 'https://download.copr.fedorainfracloud.org/results/cmdntrf/spank-cc-tmpfs_mounts/pubkey.gpg',
    repo_gpgcheck       => 0,
  }

  package { ['slurm-slurmd', 'slurm-pam_slurm']:
    ensure  => 'installed',
    require => Package['slurm'],
  }

  package { 'spank-cc-tmpfs_mounts':
    ensure  => 'installed',
    require => [
      Package['slurm-slurmd'],
      Yumrepo['spank-cc-tmpfs_mounts-copr-repo'],
    ],
  }

  file { '/etc/slurm/plugstack.conf':
    owner   => 'slurm',
    group   => 'slurm',
    content => @(EOT/L),
      required /opt/software/slurm/lib64/slurm/cc-tmpfs_mounts.so \
      bindself=/tmp bindself=/dev/shm target=/localscratch bind=/var/tmp/
      |EOT
  }

  $real_memory = $facts['memory']['system']['total_bytes'] / (1024 * 1024)
  $os_reserved_memory = lookup('profile::slurm::base::os_reserved_memory')
  consul::service { 'slurmd':
    port    => 6818,
    require => Tcp_conn_validator['consul'],
    token   => lookup('profile::consul::acl_api_token'),
    meta    => {
      cpus         => String($facts['processors']['count']),
      realmemory   => String($real_memory),
      gpus         => String($facts['nvidia_gpu_count']),
      memspeclimit => String($os_reserved_memory),
    },
  }

  pam { 'Add pam_slurm_adopt':
    ensure   => present,
    service  => 'sshd',
    type     => 'account',
    control  => 'sufficient',
    module   => 'pam_slurm_adopt.so',
    position => 'after module password-auth',
  }

  pam { 'Add pam_access':
    ensure   => present,
    service  => 'sshd',
    type     => 'account',
    control  => 'required',
    module   => 'pam_access.so',
    position => 'after module pam_slurm_adopt.so',
    require  => Pam['Add pam_slurm_adopt'],
  }

  $access_conf = '
# Allow root cronjob
+ : root : cron crond :0 tty1 tty2 tty3 tty4 tty5 tty6
# Allow admin to connect, deny all other
+:wheel:ALL
-:ALL:ALL
'

  file { '/etc/security/access.conf':
    content => $access_conf,
  }

  selinux::module { 'sshd_pam_slurm_adopt':
    ensure    => 'present',
    source_pp => 'puppet:///modules/profile/slurm/pam_slurm_adopt.pp',
  }

  selinux::module { 'slurmd':
    ensure    => 'present',
    source_pp => 'puppet:///modules/profile/slurm/slurmd.pp',
  }

  file { '/localscratch':
    ensure  => 'directory',
    seltype => 'tmp_t',
  }

  file { '/var/spool/slurmd':
    ensure => 'directory',
    owner  => 'slurm',
    group  => 'slurm',
  }

  consul_template::watch { 'slurm.conf':
    require     => File['/etc/slurm/slurm.conf.tpl'],
    config_hash => {
      perms       => '0644',
      source      => '/etc/slurm/slurm.conf.tpl',
      destination => '/etc/slurm/slurm.conf',
      command     => 'systemctl restart slurmd',
    },
  }
  consul_template::watch { 'node.conf':
    require     => File['/etc/slurm/node.conf.tpl'],
    config_hash => {
      perms       => '0644',
      source      => '/etc/slurm/node.conf.tpl',
      destination => '/etc/slurm/node.conf',
      command     => 'systemctl restart slurmd',
    },
  }

  $gres_template = @(EOT/L)
###########################################################
# Slurm's Generic Resource (GRES) configuration file
# Use NVML to gather GPU configuration information
# Information about all other GRES gathered from slurm.conf
###########################################################
<% if $gpu_count > 0 { -%>
AutoDetect=nvml
<% } -%>
|EOT

  file { '/etc/slurm/gres.conf':
    owner   => 'slurm',
    group   => 'slurm',
    content => inline_epp($gres_template, { 'gpu_count' => $facts['nvidia_gpu_count'] }),
    seltype => 'etc_t',
  }

  wait_for { 'nodeconfig_set':
    query             => 'cat /etc/slurm/node.conf',
    regex             => "^NodeName=${::facts['hostname']}",
    polling_frequency => 10,  # Wait up to 5 minutes (30 * 10 seconds).
    max_retries       => 30,
    require           => [
      Service['consul-template']
    ],
    refreshonly       => true,
    subscribe         => Package['slurm-slurmd'],
  }

  service { 'slurmd':
    ensure    => 'running',
    enable    => true,
    subscribe => [
      File['/etc/slurm/cgroup.conf'],
      File['/etc/slurm/plugstack.conf']
    ],
    require   => [
      Package['slurm-slurmd'],
      Wait_for['nodeconfig_set'],
      Wait_for['slurmctldhost_set'],
    ],
  }

  logrotate::rule { 'slurmd':
    path         => '/var/log/slurm/slurmd.log',
    rotate       => 5,
    ifempty      => false,
    copytruncate => false,
    olddir       => false,
    size         => '5M',
    compress     => true,
    create       => true,
    create_mode  => '0600',
    create_owner => 'root',
    create_group => 'root',
    postrotate   => '/usr/bin/pkill -x --signal SIGUSR2 slurmd',
  }

  exec { 'scontrol_update_state':
    command   => "scontrol update nodename=${facts['networking']['hostname']} state=idle",
    onlyif    => "sinfo -n ${facts['networking']['hostname']} -o %t -h | grep -E -q -w 'down|drain'",
    path      => ['/usr/bin', '/opt/software/slurm/bin'],
    subscribe => Service['slurmd'],
  }

  # If slurmctld server is rebooted slurmd needs to be restarted.
  # Otherwise, slurmd keeps running, but the node is not in any partition
  # and no job can be scheduled on it.
  exec { 'systemctl restart slurmd':
    onlyif  => "test $(sinfo -n ${facts['networking']['hostname']} -o %t -h | wc -l) -eq 0",
    path    => ['/usr/bin', '/opt/software/slurm/bin'],
    require => Service['slurmd'],
  }
}
