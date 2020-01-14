# Slurm base class that is included in each different profile.
# The class configures the slurm and munge users, install the
# base slurm packages and configures everything that is required
# on all types of nodes.
# @param cluster_name Specifies the name of the cluster as it appears in slurm.conf
# @param munge_key Specifies the munge secret key that allows slurm nodes to communicate
class profile::slurm::base (
  String $cluster_name,
  String $munge_key)
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
{{with tree "slurmd/" | explode }}{{range $key, $value := . -}}
{{ if and $value.nodename $value.cpus $value.realmemory -}}
NodeName={{$value.nodename}} CPUs={{$value.cpus}} RealMemory={{$value.realmemory}} {{if gt (parseInt $value.gpus) 0}}Gres=gpu:{{$value.gpus}}{{end}}
{{end -}}
{{end -}}
{{end -}}
END

  file { '/etc/slurm/node.conf.tpl':
    ensure  => 'present',
    owner   => 'slurm',
    group   => 'slurm',
    content => $node_template,
    seltype => 'etc_t'
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
      descr               => 'Copr repo for Slurm19 owned by cmdntrf',
      baseurl             => 'https://copr-be.cloud.fedoraproject.org/results/cmdntrf/Slurm19-nvml/epel-7-$basearch/',
      skip_if_unavailable => true,
      gpgcheck            => 1,
      gpgkey              => 'https://copr-be.cloud.fedoraproject.org/results/cmdntrf/Slurm19-nvml/pubkey.gpg',
      repo_gpgcheck       => 0,
    }
  } else {
    yumrepo { 'slurm-copr-repo':
      enabled             => true,
      descr               => 'Copr repo for Slurm19 owned by cmdntrf',
      baseurl             => 'https://copr-be.cloud.fedoraproject.org/results/cmdntrf/Slurm19/epel-7-$basearch/',
      skip_if_unavailable => true,
      gpgcheck            => 1,
      gpgkey              => 'https://copr-be.cloud.fedoraproject.org/results/cmdntrf/Slurm19/pubkey.gpg',
      repo_gpgcheck       => 0,
    }
  }

  package { 'slurm':
    ensure  => 'installed',
    require => [Package['munge'],
                Yumrepo['slurm-copr-repo']],
  }

  package { 'slurm-contribs':
    ensure  => 'installed',
    require => [Package['munge'],
                Yumrepo['slurm-copr-repo']],
  }

  package { 'slurm-libpmi':
    ensure  => 'installed',
    require => [Package['munge'],
                Yumrepo['slurm-copr-repo']]
  }

  file { 'cc-tmpfs_mount.so':
    ensure         => 'present',
    source         => @(EOT/L),
      https://gist.github.com/cmd-ntrf/a9305513809e7c9a104f79f0f15ec067/\
      raw/da71a07f455206e21054f019d26a277daeaa0f00/cc-tmpfs_mounts.so
      |-EOT
    path           => '/opt/software/slurm/lib64/slurm/cc-tmpfs_mounts.so',
    owner          => 'slurm',
    group          => 'slurm',
    mode           => '0755',
    checksum       => 'md5',
    checksum_value => 'ff2beaa7be1ec0238fd621938f31276c',
    require        => Package['slurm']
  }

  file { 'slurm.conf.tpl':
    ensure  => 'present',
    path    => '/etc/slurm/slurm.conf.tpl',
    content => epp('profile/slurm/slurm.conf', {'cluster_name' => $cluster_name}),
    group   => 'slurm',
    owner   => 'slurm',
    mode    => '0644',
    require => File['/etc/slurm']
  }
}

# Slurm accouting. This where is slurm accounting database and daemon is ran.
# @param password Specifies the password to access the MySQL database with user slurm.
# @param dbd_port Specfies the port on which run the slurmdbd daemon.
class profile::slurm::accounting(String $password, Integer $dbd_port = 6819) {

  consul_key_value { 'slurmdbd/hostname':
    ensure        => 'present',
    value         => $facts['hostname'],
    require       => Tcp_conn_validator['consul'],
    acl_api_token => lookup('profile::consul::acl_api_token')
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

  tcp_conn_validator { 'slurmdbd_port':
    host      => $::hostname,
    port      => $dbd_port,
    try_sleep => 5,
    timeout   => 60,
    require   => Service['slurmdbd']
  }

  $cluster_name = lookup('profile::slurm::base::cluster_name')
  exec { 'sacctmgr_add_cluster':
    command   => "sacctmgr add cluster ${cluster_name} -i",
    path      => ['/bin', '/usr/sbin', '/opt/software/slurm/bin', '/opt/software/slurm/sbin'],
    unless    => "test `sacctmgr show cluster Names=${cluster_name} -n | wc -l` == 1",
    tries     => 2,
    try_sleep => 5,
    timeout   => 5,
    notify    => Service['slurmctld'],
    require   => [Service['slurmdbd'],
                  Tcp_conn_validator['slurmdbd_port'],
                  Consul_template::Watch['slurm.conf'],
                  Consul_template::Watch['node.conf']]
  }

  $account_name = 'def-sponsor00'
  # Create account for every user
  exec { 'slurm_create_account':
    command   => @("EOT"/L),
      sacctmgr add account ${account_name} \
      -i Description='Cloud Cluster Account' Organization='Compute Canada'
      |EOT
    path      => ['/bin', '/usr/sbin', '/opt/software/slurm/bin', '/opt/software/slurm/sbin'],
    unless    => "test `sacctmgr show account Names=${account_name} -n | wc -l` == 1",
    tries     => 5,
    try_sleep => 5,
    timeout   => 5,
    require   => [Service['slurmdbd'],
                  Tcp_conn_validator['slurmdbd_port'],
                  Consul_template::Watch['slurm.conf'],
                  Consul_template::Watch['node.conf']]
  }

  # Add guest accounts to the accounting database
  $nb_accounts = lookup({ name => 'profile::freeipa::guest_accounts::nb_accounts', default_value => 0 })
  $prefix      = lookup({ name => 'profile::freeipa::guest_accounts::prefix', default_value => 'user' })
  $nb_zeros    = inline_template("<%= '0' * ('${nb_accounts}'.length - 1) %>")
  $user_range  = "${prefix}[${nb_zeros}1-${nb_accounts}]"
  exec{ 'slurm_add_user':
    command => "sacctmgr add user ${user_range} Account=${account_name} -i",
    path    => ['/bin', '/usr/sbin', '/opt/software/slurm/bin', '/opt/software/slurm/sbin'],
    unless  => "test `sacctmgr show user Names=${user_range} -n | wc -l` == ${nb_accounts}",
    require => Exec['slurm_create_account']
  }
}

# Slurm controller class. This where slurmctld is ran.
class profile::slurm::controller {
  include profile::slurm::base
  consul_key_value { 'slurmctld/hostname':
    ensure        => 'present',
    value         => $facts['hostname'],
    require       => Tcp_conn_validator['consul'],
    acl_api_token => lookup('profile::consul::acl_api_token')
  }

  $interface = split($::interfaces, ',')[0]
  $ipaddress = $::networking['interfaces'][$interface]['ip']
  consul_key_value { 'slurmctld/ip':
    ensure        => 'present',
    value         => $ipaddress,
    require       => Tcp_conn_validator['consul'],
    acl_api_token => lookup('profile::consul::acl_api_token')
  }

  package { 'slurm-slurmctld':
    ensure  => 'installed',
    require => Package['munge']
  }

  package { 'mailx':
    ensure => 'installed',
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
    require => [Package['slurm-slurmctld'],
                Consul_template::Watch['slurm.conf'],
                Consul_template::Watch['node.conf']]
  }
}

# Slurm node class. This is where slurmd is ran.
class profile::slurm::node {
  include profile::slurm::base

  consul_key_value { "slurmd/${facts['hostname']}/nodename":
    ensure        => 'present',
    value         => $facts['hostname'],
    require       => Tcp_conn_validator['consul'],
    acl_api_token => lookup('profile::consul::acl_api_token')
  }
  consul_key_value { "slurmd/${facts['hostname']}/cpus":
    ensure        => 'present',
    value         => String($facts['processors']['count']),
    require       => Tcp_conn_validator['consul'],
    acl_api_token => lookup('profile::consul::acl_api_token')
  }
  $real_memory = $facts['memory']['system']['total_bytes'] / (1024 * 1024)
  consul_key_value { "slurmd/${facts['hostname']}/realmemory":
    ensure        => 'present',
    value         => String($real_memory),
    require       => Tcp_conn_validator['consul'],
    acl_api_token => lookup('profile::consul::acl_api_token')
  }
  consul_key_value { "slurmd/${facts['hostname']}/gpus":
    ensure        => 'present',
    value         => String($facts['nvidia_gpu_count']),
    require       => Tcp_conn_validator['consul'],
    acl_api_token => lookup('profile::consul::acl_api_token')
  }

  package { 'slurm-slurmd':
    ensure => 'installed'
  }

  package { 'slurm-pam_slurm':
    ensure => 'installed'
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
<% Integer[0, $gpu_count - 1].each |$gpu| { -%>
Name=gpu
<% } -%>
<% } -%>
|EOT

  file { '/etc/slurm/gres.conf':
    ensure  => 'present',
    owner   => 'slurm',
    group   => 'slurm',
    content => inline_epp($gres_template, { 'gpu_count' => $facts['nvidia_gpu_count'] }),
    seltype => 'etc_t'
  }

  service { 'slurmd':
    ensure    => 'running',
    enable    => true,
    subscribe => [File['/etc/slurm/cgroup.conf'],
                  File['/etc/slurm/plugstack.conf']],
    require   => [Package['slurm-slurmd'],
                  Consul_template::Watch['slurm.conf'],
                  Consul_template::Watch['node.conf']]
  }

  exec { 'scontrol_update_state':
    command   => "scontrol update nodename=${::hostname} state=idle",
    onlyif    => "sinfo -n ${::hostname} -o %t -h | grep -E -q -w 'down|drain'",
    path      => ['/usr/bin', '/opt/software/slurm/bin'],
    subscribe => Service['slurmd']
  }
}

# Slurm submitter class. This is for instances that neither run slurmd
# and slurmctld but still need to be able to communicate with the slurm
# controller through Slurm command-line tools.
class profile::slurm::submitter {
  include profile::slurm::base

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
