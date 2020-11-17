# Slurm base class that is included in each different profile.
# The class configures the slurm and munge users, install the
# base slurm packages and configures everything that is required
# on all types of nodes.
# @param cluster_name Specifies the name of the cluster as it appears in slurm.conf
# @param munge_key Specifies the munge secret key that allows slurm nodes to communicate
class profile::slurm::base (
  String $cluster_name,
  String $munge_key,
  Integer[19, 20] $slurm_version = 19)
{
  group { 'slurm':
    ensure => 'present',
    gid    =>  '2001'
  }

  user { 'slurm':
    ensure  => 'present',
    groups  => 'slurm',
    uid     => '2001',
    home    => '/var/lib/slurm',
    comment => 'Slurm workload manager',
    shell   => '/bin/bash',
    before  => Package['slurm']
  }

  group { 'munge':
    ensure => 'present',
    gid    =>  '2002'
  }

  user { 'munge':
    ensure  => 'present',
    groups  => 'munge',
    uid     => '2002',
    home    => '/var/lib/munge',
    comment => 'MUNGE Uid N Gid Emporium',
    shell   => '/sbin/nologin',
    before  => Package['munge']
  }

  package { 'munge':
    ensure  => 'installed',
    require => Yumrepo['epel']
  }

  file { '/var/log/slurm':
    ensure => 'directory',
    owner  => 'slurm',
    group  => 'slurm'
  }

  file { '/var/spool/slurm':
    ensure => 'directory',
    owner  => 'slurm',
    group  => 'slurm'
  }

  file { '/etc/slurm':
    ensure  => 'directory',
    owner   => 'slurm',
    group   => 'slurm',
    seltype => 'usr_t'
  }

  file { '/etc/munge':
    ensure => 'directory',
    owner  => 'munge',
    group  => 'munge'
  }

  file { '/etc/slurm/cgroup.conf':
    ensure => 'present',
    owner  => 'slurm',
    group  => 'slurm',
    source => 'puppet:///modules/profile/slurm/cgroup.conf'
  }

  file { '/etc/slurm/cgroup_allowed_devices_file.conf':
    ensure => 'present',
    owner  => 'slurm',
    group  => 'slurm',
    source => 'puppet:///modules/profile/slurm/cgroup_allowed_devices_file.conf'
  }

  file { '/etc/slurm/epilog':
    ensure => 'present',
    owner  => 'slurm',
    group  => 'slurm',
    source => 'puppet:///modules/profile/slurm/epilog',
    mode   => '0755'
  }

  $node_template = @(END)
# Nodes definition
{{ range service "slurmd" -}}
NodeName={{.Node}} CPUs={{.ServiceMeta.cpus}} RealMemory={{.ServiceMeta.realmemory}} {{if gt (parseInt .ServiceMeta.gpus) 0}}Gres=gpu:{{.ServiceMeta.gpus}}{{end}}
{{ end -}}
END

  file { '/etc/slurm/node.conf.tpl':
    ensure  => 'present',
    owner   => 'slurm',
    group   => 'slurm',
    content => $node_template,
    seltype => 'etc_t',
    notify  => Service['consul-template'],
  }

  $slurm_path = @(END)
# Add Slurm custom paths for local users
if [[ $UID -lt 10000 ]]; then
  export SLURM_HOME=/opt/software/slurm

  export PATH=$SLURM_HOME/bin:$PATH
  export MANPATH=$SLURM_HOME/share/man:$MANPATH
  export LD_LIBRARY_PATH=$SLURM_HOME/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
fi
if [[ $UID -eq 0 ]]; then
   export PATH=$SLURM_HOME/sbin:$PATH
fi
END

  file { '/etc/profile.d/z-00-slurm.sh':
    ensure  => 'present',
    content => $slurm_path
  }

  file { '/etc/munge/munge.key':
    ensure  => 'present',
    owner   => 'munge',
    group   => 'munge',
    mode    => '0400',
    content => $munge_key,
    before  => Service['munge']
  }

  service { 'munge':
    ensure    => 'running',
    enable    => true,
    subscribe => File['/etc/munge/munge.key'],
    require   => Package['munge']
  }

  if $facts['nvidia_gpu_count'] > 0 {
    yumrepo { 'slurm-copr-repo':
      enabled             => true,
      descr               => "Copr repo for Slurm${slurm_version} owned by cmdntrf",
      baseurl             => "https://copr-be.cloud.fedoraproject.org/results/cmdntrf/Slurm${slurm_version}-nvml/epel-\$releasever-\$basearch/",
      skip_if_unavailable => true,
      gpgcheck            => 1,
      gpgkey              => "https://copr-be.cloud.fedoraproject.org/results/cmdntrf/Slurm${slurm_version}-nvml/pubkey.gpg",
      repo_gpgcheck       => 0,
    }
  } else {
    yumrepo { 'slurm-copr-repo':
      enabled             => true,
      descr               => "Copr repo for Slurm${slurm_version} owned by cmdntrf",
      baseurl             => "https://copr-be.cloud.fedoraproject.org/results/cmdntrf/Slurm${slurm_version}/epel-\$releasever-\$basearch/",
      skip_if_unavailable => true,
      gpgcheck            => 1,
      gpgkey              => "https://copr-be.cloud.fedoraproject.org/results/cmdntrf/Slurm${slurm_version}/pubkey.gpg",
      repo_gpgcheck       => 0,
    }
  }

  package { 'slurm':
    ensure  => 'installed',
    require => [Package['munge'],
                Yumrepo['slurm-copr-repo']],
  }

  package { ['slurm-contribs', 'slurm-perlapi' ]:
    ensure  => 'installed',
    require => [Package['munge'],
                Yumrepo['slurm-copr-repo']],
  }

  package { 'slurm-libpmi':
    ensure  => 'installed',
    require => [Package['munge'],
                Yumrepo['slurm-copr-repo']]
  }

  file { 'slurm.conf.tpl':
    ensure  => 'present',
    path    => '/etc/slurm/slurm.conf.tpl',
    content => epp('profile/slurm/slurm.conf', {'cluster_name' => $cluster_name}),
    group   => 'slurm',
    owner   => 'slurm',
    mode    => '0644',
    require => File['/etc/slurm'],
    notify  => Service['consul-template'],
  }

  wait_for { 'slurmctldhost_set':
    query             => 'cat /etc/slurm/slurm.conf',
    regex             => '^SlurmctldHost=',
    polling_frequency => 10,  # Wait up to 5 minutes (30 * 10 seconds).
    max_retries       => 30,
    require           => [
      Service['consul-template']
    ],
    refreshonly       => true,
    subscribe         => File['/etc/slurm/node.conf.tpl'],
  }

}

# Slurm accouting. This where is slurm accounting database and daemon is ran.
# @param password Specifies the password to access the MySQL database with user slurm.
# @param dbd_port Specfies the port on which run the slurmdbd daemon.
class profile::slurm::accounting(String $password, Integer $dbd_port = 6819) {

  consul::service { 'slurmdbd':
    port    => $dbd_port,
    require => Tcp_conn_validator['consul'],
    token   => lookup('profile::consul::acl_api_token'),
  }

  $override_options = {
    'mysqld' => {
      'innodb_buffer_pool_size' => '1024M',
      'innodb_log_file_size' => '64M',
      'innodb_lock_wait_timeout' => '900',
    }
  }

  class { 'mysql::server':
    remove_default_accounts => true,
    override_options        => $override_options
  }

  mysql::db { 'slurm_acct_db':
    ensure   => present,
    user     => 'slurm',
    password => $password,
    host     => 'localhost',
    grant    => ['ALL'],
  }

  file { '/etc/slurm/slurmdbd.conf':
    ensure  => present,
    content => epp('profile/slurm/slurmdbd.conf',
      { 'dbd_host'     => $::hostname,
        'dbd_port'     => $dbd_port,
        'storage_pass' => $password
      }),
    owner   => 'slurm',
    mode    => '0600',
  }

  package { 'slurm-slurmdbd':
    ensure  => present,
    require => [Package['munge'],
                Yumrepo['slurm-copr-repo']],
  }

  service { 'slurmdbd':
    ensure  => running,
    enable  => true,
    require => [Package['slurm-slurmdbd'],
                File['/etc/slurm/slurmdbd.conf'],
                Mysql::Db['slurm_acct_db']],
    before  => Service['slurmctld']
  }

  wait_for { 'slurmdbd_started':
    query             => 'cat /var/log/slurm/slurmdbd.log',
    regex             => '^\[[.:0-9\-T]{23}\] slurmdbd version \d+.\d+.\d+ started$',
    polling_frequency => 10,  # Wait up to 4 minutes (24 * 10 seconds).
    max_retries       => 24,
    refreshonly       => true,
    subscribe         => Service['slurmdbd']
  }

  $cluster_name = lookup('profile::slurm::base::cluster_name')
  exec { 'sacctmgr_add_cluster':
    command   => "sacctmgr add cluster ${cluster_name} -i | grep -qP '(already exists|Adding Cluster)'",
    path      => ['/bin', '/usr/sbin', '/opt/software/slurm/bin', '/opt/software/slurm/sbin'],
    unless    => "test `sacctmgr show cluster Names=${cluster_name} -n | wc -l` == 1",
    tries     => 4,
    try_sleep => 15,
    timeout   => 15,
    require   => [
      Service['slurmdbd'],
      Wait_for['slurmdbd_started'],
      Wait_for['slurmctldhost_set'],
    ],
    before    => [
      Service['slurmctld']
    ],
  }
}

# Slurm controller class. This where slurmctld is ran.
class profile::slurm::controller {
  contain profile::slurm::base
  include profile::mail::server

  consul::service { 'slurmctld':
    port    => 6817,
    require => Tcp_conn_validator['consul'],
    token   => lookup('profile::consul::acl_api_token'),
  }

  package { 'slurm-slurmctld':
    ensure  => 'installed',
    require => Package['munge']
  }

  consul_template::watch { 'slurm.conf':
    require     => File['/etc/slurm/slurm.conf.tpl'],
    config_hash => {
      perms       => '0644',
      source      => '/etc/slurm/slurm.conf.tpl',
      destination => '/etc/slurm/slurm.conf',
      command     => 'systemctl restart slurmctld || true',
    }
  }

  consul_template::watch { 'node.conf':
    require     => File['/etc/slurm/node.conf.tpl'],
    config_hash => {
      perms       => '0644',
      source      => '/etc/slurm/node.conf.tpl',
      destination => '/etc/slurm/node.conf',
      command     => 'systemctl restart slurmctld || true',
    }
  }

  service { 'slurmctld':
    ensure  => 'running',
    enable  => true,
    require => [
      Package['slurm-slurmctld'],
      Wait_for['slurmctldhost_set'],
    ]
  }
}

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
    require => Package['slurm']
  }

  package { 'spank-cc-tmpfs_mounts':
    ensure  => 'installed',
    require => [
      Package['slurm-slurmd'],
      Yumrepo['spank-cc-tmpfs_mounts-copr-repo'],
    ]
  }

  file { '/etc/slurm/plugstack.conf':
    ensure  => 'present',
    owner   => 'slurm',
    group   => 'slurm',
    content => @(EOT/L),
      required /opt/software/slurm/lib64/slurm/cc-tmpfs_mounts.so \
      bindself=/tmp bindself=/dev/shm target=/localscratch bind=/var/tmp/
      |EOT
  }

  $real_memory = $facts['memory']['system']['total_bytes'] / (1024 * 1024)
  consul::service { 'slurmd':
    port    => 6818,
    require => Tcp_conn_validator['consul'],
    token   => lookup('profile::consul::acl_api_token'),
    meta    => {
      cpus       => String($facts['processors']['count']),
      realmemory => String($real_memory),
      gpus       => String($facts['nvidia_gpu_count']),
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
    require  => Pam['Add pam_slurm_adopt']
  }

  $access_conf = '
# Allow root cronjob
+ : root : cron crond :0 tty1 tty2 tty3 tty4 tty5 tty6
# Allow admin to connect, deny all other
+:wheel:ALL
-:ALL:ALL
'

  file { '/etc/security/access.conf':
    ensure  => present,
    content => $access_conf
  }

  selinux::module { 'sshd_pam_slurm_adopt':
    ensure    => 'present',
    source_pp => 'puppet:///modules/profile/slurm/pam_slurm_adopt.pp',
  }

  file { '/localscratch':
    ensure  => 'directory',
    seltype => 'default_t'
  }

  file { '/var/spool/slurmd':
    ensure => 'directory',
    owner  => 'slurm',
    group  => 'slurm'
  }

  consul_template::watch { 'slurm.conf':
    require     => File['/etc/slurm/slurm.conf.tpl'],
    config_hash => {
      perms       => '0644',
      source      => '/etc/slurm/slurm.conf.tpl',
      destination => '/etc/slurm/slurm.conf',
      command     => 'systemctl restart slurmd',
    }
  }
  consul_template::watch { 'node.conf':
    require     => File['/etc/slurm/node.conf.tpl'],
    config_hash => {
      perms       => '0644',
      source      => '/etc/slurm/node.conf.tpl',
      destination => '/etc/slurm/node.conf',
      command     => 'systemctl restart slurmd',
    }
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
    ensure  => 'present',
    owner   => 'slurm',
    group   => 'slurm',
    content => inline_epp($gres_template, { 'gpu_count' => $facts['nvidia_gpu_count'] }),
    seltype => 'etc_t'
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
    subscribe         => Package['slurm-slurmd']
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
    ]
  }

  exec { 'scontrol_update_state':
    command   => "scontrol update nodename=${::hostname} state=idle",
    onlyif    => "sinfo -n ${::hostname} -o %t -h | grep -E -q -w 'down|drain'",
    path      => ['/usr/bin', '/opt/software/slurm/bin'],
    subscribe => Service['slurmd']
  }

  # If slurmctld server is rebooted slurmd needs to be restarted.
  # Otherwise, slurmd keeps running, but the node is not in any partition
  # and no job can be scheduled on it.
  exec { 'systemctl restart slurmd':
    onlyif  => "test $(sinfo -n ${::hostname} -o %t -h | wc -l) -eq 0",
    path    => ['/usr/bin', '/opt/software/slurm/bin'],
    require => Service['slurmd'],
  }
}

# Slurm submitter class. This is for instances that neither run slurmd
# and slurmctld but still need to be able to communicate with the slurm
# controller through Slurm command-line tools.
class profile::slurm::submitter {
  contain profile::slurm::base

  # SELinux policy required to allow confined users to submit job with Slurm 19
  # and Slurm 20. Slurm commands tries to write to a socket in /var/run/munge.
  # Confined users cannot stat this file, neither write to it. The policy
  # allows user_t to getattr and write var_run_t sock file.
  # To get the policy, we had to disable dontaudit rules with : sudo semanage -DB
  selinux::module { 'munge_socket':
    ensure    => 'present',
    source_pp => 'puppet:///modules/profile/slurm/munge_socket.pp',
  }

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
