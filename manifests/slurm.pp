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
<% for i in 1..250 do -%>
NodeName=node<%= i %> State=FUTURE
<% end -%>
END

  file { '/etc/slurm/node.conf':
    ensure  => 'present',
    owner   => 'slurm',
    group   => 'slurm',
    replace => false,
    content => inline_template($node_template),
    seltype => 'etc_t'
  }

  file { '/etc/slurm/plugstack.conf':
    ensure  => 'present',
    owner   => 'slurm',
    group   => 'slurm',
    content => 'required /opt/software/slurm/lib64/slurm/cc-tmpfs_mounts.so bindself=/tmp bindself=/dev/shm target=/localscratch bind=/var/tmp/'
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

  yumrepo { 'slurm-copr-repo':
    enabled             => true,
    descr               => 'Copr repo for Slurm19 owned by cmdntrf',
    baseurl             => 'https://copr-be.cloud.fedoraproject.org/results/cmdntrf/Slurm19/epel-7-$basearch/',
    skip_if_unavailable => true,
    gpgcheck            => 1,
    gpgkey              => 'https://copr-be.cloud.fedoraproject.org/results/cmdntrf/Slurm19/pubkey.gpg',
    repo_gpgcheck       => 0,
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
    source         => 'https://gist.github.com/cmd-ntrf/a9305513809e7c9a104f79f0f15ec067/raw/da71a07f455206e21054f019d26a277daeaa0f00/cc-tmpfs_mounts.so',
    path           => '/opt/software/slurm/lib64/slurm/cc-tmpfs_mounts.so',
    owner          => 'slurm',
    group          => 'slurm',
    mode           => '0755',
    checksum       => 'md5',
    checksum_value => 'ff2beaa7be1ec0238fd621938f31276c',
    require        => Package['slurm']
  }
}

class profile::slurm::accounting(String $password, Integer $dbd_port = 6819) {

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

  $slurm_conf = "
## Accounting
AccountingStorageHost=${::hostname}
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageTRES=gres/gpu,cpu,mem
#AccountingStorageEnforce=limits
JobAcctGatherType=jobacct_gather/linux
JobAcctGatherFrequency=task=30
JobAcctGatherParams=NoOverMemoryKill,UsePSS
"
  concat::fragment { 'slurm.conf_slurmdbd':
    target  => '/etc/slurm/slurm.conf',
    order   => '50',
    content => $slurm_conf
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
                Concat::Fragment['slurm.conf_slurmdbd']],
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
    tries     => 5,
    try_sleep => 5,
    require   => [Service['slurmdbd'], Tcp_conn_validator['slurmdbd_port']],
    notify    => Service['slurmctld']
  }

  $account_name = 'def-sponsor00'
  # Create account for every user
  exec { 'slurm_create_account':
    command   => "sacctmgr add account ${account_name} -i Description='Cloud Cluster Account' Organization='Compute Canada'",
    path      => ['/bin', '/usr/sbin', '/opt/software/slurm/bin', '/opt/software/slurm/sbin'],
    unless    => "test `sacctmgr show account Names=${account_name} -n | wc -l` == 1",
    tries     => 5,
    try_sleep => 5,
    require   => [Service['slurmdbd'], Tcp_conn_validator['slurmdbd_port']],
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

class profile::slurm::controller {
  include profile::slurm::base

  package { 'slurm-slurmctld':
    ensure  => 'installed',
    require => Package['munge']
  }

  package { 'mailx':
    ensure => 'installed',
  }

  service { 'slurmctld':
    ensure  => 'running',
    enable  => true,
    require => Package['slurm-slurmctld']
  }

  concat { '/etc/slurm/slurm.conf':
    ensure => 'present',
    group  => 'slurm',
    owner  => 'slurm',
    mode   => '0644'
  }

  $cluster_name = lookup('profile::slurm::base::cluster_name')
  concat::fragment { 'slurm.conf_header':
    target  => '/etc/slurm/slurm.conf',
    content => epp('profile/slurm/slurm.conf', {'cluster_name' => $cluster_name}),
    order   => '01'
  }

  concat::fragment { 'slurm.conf_slurmctld':
    target  => '/etc/slurm/slurm.conf',
    order   => '10',
    content => "SlurmctldHost=${::hostname}(${::ipaddress})",
    notify  => Service['slurmctld']
  }
}

class profile::slurm::node {
  include profile::slurm::base

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

  service { 'slurmd':
    ensure    => 'running',
    enable    => true,
    require   => Package['slurm-slurmd'],
    subscribe => [File['/etc/slurm/cgroup.conf'],
                  File['/etc/slurm/plugstack.conf']]
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

  exec { 'slurm_config':
    command => "flock /etc/slurm/node.conf.lock sed -i \"s/NodeName=${::hostname} .*/$(slurmd -C | head -n 1)/g\" /etc/slurm/node.conf",
    path    => ['/bin', '/usr/sbin', '/opt/software/slurm/bin', '/opt/software/slurm/sbin'],
    unless  => 'grep -q "$(slurmd -C | head -n 1)" /etc/slurm/node.conf',
    notify  => Service['slurmd']
  }

  exec { 'scontrol reconfigure':
    path        => ['/usr/bin', '/opt/software/slurm/bin'],
    subscribe   => Exec['slurm_config'],
    refreshonly => true,
    returns     => [0, 1]
  }

  exec { 'scontrol_update_state':
    command   => "scontrol update nodename=${::hostname} state=idle",
    onlyif    => "test $(sinfo -n ${::hostname} -o %t -h) = down",
    path      => ['/usr/bin', '/opt/software/slurm/bin'],
    subscribe => Service['slurmd']
  }
}

class profile::slurm::submitter {
  include profile::slurm::base
}
