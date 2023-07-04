# Slurm base class that is included in each different profile.
# The class configures the slurm and munge users, install the
# base slurm packages and configures everything that is required
# on all types of nodes.
# @param cluster_name Specifies the name of the cluster as it appears in slurm.conf
# @param munge_key Specifies the munge secret key that allows slurm nodes to communicate
# @param slurm_version Specifies which version of Slurm to install
# @param os_reserved_memory Specifies the amount of memory reserved for the operating system in compute node
class profile::slurm::base (
  String $cluster_name,
  String $munge_key,
  Enum['20.11', '21.08', '22.05'] $slurm_version,
  Integer $os_reserved_memory,
  Integer $suspend_time = 3600,
  Integer $resume_timeout = 3600,
  Boolean $force_slurm_in_path = false,
  Boolean $enable_x11_forwarding = true,
)
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
    ensure  => 'present',
    owner   => 'slurm',
    group   => 'slurm',
    content => epp('profile/slurm/cgroup.conf',
      {
        'slurm_version' => $slurm_version,
      }
    ),
  }

  if versioncmp($slurm_version, '22.05') < 0 {
    file { '/etc/slurm/cgroup_allowed_devices_file.conf':
      ensure => 'present',
      owner  => 'slurm',
      group  => 'slurm',
      source => 'puppet:///modules/profile/slurm/cgroup_allowed_devices_file.conf'
    }
  }

  file { '/etc/slurm/epilog':
    ensure => 'present',
    owner  => 'slurm',
    group  => 'slurm',
    source => 'puppet:///modules/profile/slurm/epilog',
    mode   => '0755'
  }

  $slurm_path = @(END)
<% if ! $force_slurm_in_path { %>if [[ $UID -lt <%= $uid_max %> ]]; then<% } %>
  export SLURM_HOME=/opt/software/slurm
  export PATH=$SLURM_HOME/bin:$PATH
  export MANPATH=$SLURM_HOME/share/man:$MANPATH
  export LD_LIBRARY_PATH=$SLURM_HOME/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
<% if ! $force_slurm_in_path { %>fi<% } %>
END

  file { '/etc/profile.d/z-00-slurm.sh':
    ensure  => 'present',
    content => inline_epp(
      $slurm_path,
      {
        'force_slurm_in_path' => $force_slurm_in_path,
        'uid_max'             => $facts['uid_max'],
      }
    ),
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

  $yumrepo_prefix = "https://download.copr.fedorainfracloud.org/results/cmdntrf/Slurm${slurm_version}/"
  yumrepo { 'slurm-copr-repo':
    enabled             => true,
    descr               => "Copr repo for Slurm${slurm_version} owned by cmdntrf",
    baseurl             => "${yumrepo_prefix}/epel-\$releasever-\$basearch/",
    skip_if_unavailable => true,
    gpgcheck            => 1,
    gpgkey              => "${yumrepo_prefix}/pubkey.gpg",
    repo_gpgcheck       => 0,
  }

  package { 'slurm':
    ensure  => 'installed',
    name    => "slurm-${slurm_version}*",
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

  $instances = lookup('terraform.instances')
  $nodes = $instances.filter|$key, $attr| { 'node' in $attr['tags'] }
  $suspend_exc_nodes = keys($nodes.filter|$key, $attr|{ !('pool' in $attr['tags']) })
  $partition_names = unique($nodes.map |$key, $attr| { $attr['prefix'] })
  $partitions = Hash($partition_names.map | $name | { [$name, { 'nodes' => keys($nodes.filter|$key, $attr | { $name == $attr['prefix'] }) } ] })
  file { '/etc/slurm/slurm.conf':
    ensure  => 'present',
    content => epp('profile/slurm/slurm.conf',
      {
        'cluster_name'          => $cluster_name,
        'slurm_version'         => $slurm_version,
        'enable_x11_forwarding' => $enable_x11_forwarding,
        'nb_nodes'              => length($nodes),
        'suspend_exc_nodes'     => join($suspend_exc_nodes, ','),
        'resume_timeout'        => $resume_timeout,
        'suspend_time'          => $suspend_time,
        'memlimit'              => $os_reserved_memory,
        'partitions'            => $partitions,
      }),
    group   => 'slurm',
    owner   => 'slurm',
    mode    => '0644',
    require => File['/etc/slurm'],
  }

  file { '/etc/slurm/slurm-consul.tpl':
    ensure => 'present',
    source => 'puppet:///modules/profile/slurm/slurm-consul.tpl',
    notify => Service['consul-template'],
  }

  wait_for { 'slurmctldhost_set':
    query             => 'cat /etc/slurm/slurm-consul.conf',
    regex             => '^SlurmctldHost=',
    polling_frequency => 10,  # Wait up to 5 minutes (30 * 10 seconds).
    max_retries       => 30,
    require           => [
      Service['consul-template'],
      Class['consul::reload_service'],
    ],
    refreshonly       => true,
    subscribe         => File['/etc/slurm/slurm-consul.tpl'],
  }

  # SELinux policy required to allow confined users to submit job with Slurm 19, 20, 21.
  # Slurm commands tries to write to a socket in /var/run/munge.
  # Confined users cannot stat this file, neither write to it. The policy
  # allows user_t to getattr and write var_run_t sock file.
  # To get the policy, we had to disable dontaudit rules with : sudo semanage -DB
  selinux::module { 'munge_socket':
    ensure    => 'present',
    source_pp => 'puppet:///modules/profile/slurm/munge_socket.pp',
  }

  file {'/etc/slurm/nodes.conf':
    ensure  => 'present',
    owner   => 'slurm',
    group   => 'slurm',
    seltype => 'etc_t',
    content => epp('profile/slurm/nodes.conf',
      {
        'nodes'    => $nodes,
        'memlimit' => $os_reserved_memory,
        'weights'  => slurm_compute_weights($nodes),
      }),
  }

  file { '/etc/slurm/gres.conf':
    ensure  => 'present',
    owner   => 'slurm',
    group   => 'slurm',
    content => epp('profile/slurm/gres.conf',
      {
        'nodes' => $nodes,
      }
    ),
    seltype => 'etc_t'
  }

  file { '/opt/software/slurm/bin/cond_restart_slurm_services':
    require => Package['slurm'],
    mode    => '0755',
    content => @("EOT"),
#!/bin/bash
{
  /usr/bin/systemctl -q is-active slurmd && /usr/bin/systemctl restart slurmd || /usr/bin/true
  /usr/bin/systemctl -q is-active slurmctld && /usr/bin/systemctl restart slurmctld || /usr/bin/true
} &> /var/log/slurm/cond_restart_slurm_services.log
|EOT
  }


  consul_template::watch { 'slurm-consul.conf':
    require     => [
      File['/etc/slurm/slurm-consul.tpl'],
      File['/opt/software/slurm/bin/cond_restart_slurm_services'],
    ],
    config_hash => {
      perms       => '0644',
      source      => '/etc/slurm/slurm-consul.tpl',
      destination => '/etc/slurm/slurm-consul.conf',
      command     => '/opt/software/slurm/bin/cond_restart_slurm_services',
    }
  }

}

# Slurm accouting. This where is slurm accounting database and daemon is ran.
# @param password Specifies the password to access the MySQL database with user slurm.
# @param dbd_port Specfies the port on which run the slurmdbd daemon.
class profile::slurm::accounting(
  String $password,
  Hash[String, Any] $options = {},
  Array[String] $admins = [],
  Hash[String, Hash] $accounts = {},
  Hash[String, Array[String]] $users = {},
  Integer $dbd_port = 6819
) {

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
      { 'dbd_host'     => $facts['networking']['hostname'],
        'dbd_port'     => $dbd_port,
        'storage_pass' => $password
      }),
    owner   => 'slurm',
    mode    => '0600',
  }

  $slurm_version = lookup('profile::slurm::base::slurm_version')
  package { 'slurm-slurmdbd':
    ensure  => present,
    name    => "slurm-slurmdbd-${slurm_version}*",
    require => [Package['munge'],
                Yumrepo['slurm-copr-repo']],
  }

  service { 'slurmdbd':
    ensure    => running,
    enable    => true,
    require   => [
      Package['slurm-slurmdbd'],
      File['/etc/slurm/slurmdbd.conf'],
    ],
    subscribe => [
      Mysql::Db['slurm_acct_db'],
    ],
    before    => Service['slurmctld']
  }

  wait_for { 'slurmdbd_started':
    query             => 'cat /var/log/slurm/slurmdbd.log',
    regex             => '^\[[.:0-9\-T]{23}\] slurmdbd version \d+.\d+.\d+(-\d+){0,1} started$',
    polling_frequency => 10,  # Wait up to 4 minutes (24 * 10 seconds).
    max_retries       => 24,
    refreshonly       => true,
    subscribe         => Service['slurmdbd']
  }

  $cluster_name = lookup('profile::slurm::base::cluster_name')
  file { '/etc/slurm/sacct.cfg':
    ensure  => present,
    content => epp('profile/slurm/sacct.cfg', {
      cluster         => $cluster_name,
      cluster_options => $options,
      admins          => $admins,
      accounts        => $accounts,
      users           => $users
    }),
    notify  => Exec['sacctmgr_load_cfg']
  }

  exec { 'sacctmgr_load_cfg':
    command     => 'sacctmgr load file=/etc/slurm/sacct.cfg -i',
    path        => ['/bin', '/usr/sbin', '/opt/software/slurm/bin', '/opt/software/slurm/sbin'],
    refreshonly => true,
    tries       => 4,
    try_sleep   => 15,
    timeout     => 15,
    require     => [
      Service['slurmdbd'],
      Wait_for['slurmdbd_started'],
      Wait_for['slurmctldhost_set'],
    ],
    before      => [
      Service['slurmctld']
    ],
  }

  logrotate::rule { 'slurmdbd':
    path         => '/var/log/slurm/slurmdbd.log',
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
    postrotate   => '/usr/bin/pkill -x --signal SIGUSR2 slurmdbd',
  }

}

# Slurm controller class. This where slurmctld is ran.
class profile::slurm::controller (
  String $autoscale_version,
  String $selinux_context = 'user_u:user_r:user_t:s0',
  String $tfe_token = '',
  String $tfe_workspace = '',
  String $tfe_var_pool = 'pool',
) {
  contain profile::slurm::base
  include profile::mail::server

  file { '/usr/sbin/slurm_mail':
    ensure => 'present',
    source => 'puppet:///modules/profile/slurm/slurm_mail',
    mode   => '0755',
  }

  ensure_packages(['python3'], { ensure => 'present' })

  $autoscale_env_prefix = '/opt/software/slurm/autoscale_env'
  exec { 'autoscale_slurm_env':
    command => "python3 -m venv ${autoscale_env_prefix}",
    creates => "${autoscale_env_prefix}/bin/activate",
    require => [
      Package['python3'], Package['slurm']
    ],
    path    => ['/usr/bin'],
  }

  exec { 'autoscale_slurm_env_upgrade_pip':
    command     => 'pip install --upgrade pip',
    subscribe   => Exec['autoscale_slurm_env'],
    refreshonly => true,
    path        => ["${autoscale_env_prefix}/bin"],
  }


  $py3_version = lookup('os::redhat::python3::version')
  exec { 'autoscale_slurm_tf_cloud_install':
    command => "pip install https://github.com/MagicCastle/slurm-autoscale-tfe/archive/refs/tags/v${autoscale_version}.tar.gz",
    creates => "${autoscale_env_prefix}/lib/python${py3_version}/site-packages/slurm_autoscale_tfe-${autoscale_version}.dist-info",
    require => [
      Exec['autoscale_slurm_env'], Exec['autoscale_slurm_env_upgrade_pip']
    ],
    path    => ["${autoscale_env_prefix}/bin"]
  }

  file { '/etc/slurm/env.secrets':
    ensure  => 'present',
    owner   => 'slurm',
    mode    => '0600',
    content => @("EOT")
export TFE_TOKEN=${tfe_token}
export TFE_WORKSPACE=${tfe_workspace}
export TFE_VAR_POOL=${tfe_var_pool}
|EOT
  }

  file { '/usr/bin/slurm_resume':
    ensure  => 'present',
    mode    => '0755',
    seltype => 'bin_t',
    content => @("EOT")
#!/bin/bash
{
  source /etc/slurm/env.secrets
  ${autoscale_env_prefix}/bin/slurm_resume $@
} &>> /var/log/slurm/slurm_resume.log
|EOT
  }

  file { '/usr/bin/slurm_suspend':
    ensure  => 'present',
    mode    => '0755',
    seltype => 'bin_t',
    content => @("EOT")
#!/bin/bash
{
  source /etc/slurm/env.secrets
  ${autoscale_env_prefix}/bin/slurm_suspend $@
} &>> /var/log/slurm/slurm_suspend.log
|EOT
  }


  $slurm_version = lookup('profile::slurm::base::slurm_version')
  if versioncmp($slurm_version, '21.08') >= 0 {
    file { '/etc/slurm/job_submit.lua':
      ensure  => 'present',
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
    before  => Wait_for['slurmctldhost_set'],
  }

  package { 'slurm-slurmctld':
    ensure  => 'installed',
    require => Package['munge']
  }

  service { 'slurmctld':
    ensure    => 'running',
    enable    => true,
    require   => [
      Package['slurm-slurmctld'],
      Wait_for['slurmctldhost_set'],
    ],
    subscribe => [
      File['/etc/slurm/slurm.conf'],
      File['/etc/slurm/gres.conf'],
      File['/etc/slurm/nodes.conf'],
    ]
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

# Slurm node class. This is where slurmd is ran.
class profile::slurm::node {
  contain profile::slurm::base

  $slurm_version = lookup('profile::slurm::base::slurm_version')
  if versioncmp($slurm_version, '22.05') >= 0 {
    $cc_tmpfs_mounts_url = 'https://download.copr.fedorainfracloud.org/results/cmdntrf/spank-cc-tmpfs_mounts-22.05/'
  } else {
    $cc_tmpfs_mounts_url = 'https://download.copr.fedorainfracloud.org/results/cmdntrf/spank-cc-tmpfs_mounts/'
  }

  yumrepo { 'spank-cc-tmpfs_mounts-copr-repo':
    enabled             => true,
    descr               => 'Copr repo for spank-cc-tmpfs_mounts owned by cmdntrf',
    baseurl             => "${cc_tmpfs_mounts_url}/epel-\$releasever-\$basearch/",
    skip_if_unavailable => true,
    gpgcheck            => 1,
    gpgkey              => "${cc_tmpfs_mounts_url}/pubkey.gpg",
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

  selinux::module { 'slurmd':
    ensure    => 'present',
    source_pp => 'puppet:///modules/profile/slurm/slurmd.pp',
  }

  file { '/localscratch':
    ensure  => 'directory',
    seltype => 'tmp_t'
  }

  file { '/var/spool/slurmd':
    ensure => 'directory',
    owner  => 'slurm',
    group  => 'slurm'
  }

  service { 'slurmd':
    ensure    => 'running',
    enable    => true,
    subscribe => [
      File['/etc/slurm/cgroup.conf'],
      File['/etc/slurm/plugstack.conf'],
      File['/etc/slurm/slurm.conf'],
      File['/etc/slurm/nodes.conf'],
      File['/etc/slurm/gres.conf'],
    ],
    require   => [
      Package['slurm-slurmd'],
      Wait_for['slurmctldhost_set'],
    ]
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

  $hostname = $facts['networking']['hostname']
  exec { 'scontrol_update_state':
    command   => "scontrol update nodename=${hostname} state=idle",
    onlyif    => "sinfo -n ${hostname} -o %t -h | grep -E -q -w 'down|drain'",
    path      => ['/usr/bin', '/opt/software/slurm/bin'],
    subscribe => Service['slurmd']
  }

  # If slurmctld server is rebooted slurmd needs to be restarted.
  # Otherwise, slurmd keeps running, but the node is not in any partition
  # and no job can be scheduled on it.
  exec { 'systemctl restart slurmd':
    onlyif  => "test $(sinfo -n ${hostname} -o %t -h | wc -l) -eq 0",
    path    => ['/usr/bin', '/opt/software/slurm/bin'],
    require => Service['slurmd'],
  }
}

# Slurm submitter class. This is for instances that neither run slurmd
# and slurmctld but still need to be able to communicate with the slurm
# controller through Slurm command-line tools.
class profile::slurm::submitter {
  contain profile::slurm::base
}
