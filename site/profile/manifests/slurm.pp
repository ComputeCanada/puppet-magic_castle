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
  Enum['23.11', '24.05', '24.11', '25.05'] $slurm_version,
  Integer $os_reserved_memory,
  Integer $suspend_time = 3600,
  Integer $suspend_rate = 20,
  Integer $resume_timeout = 3600,
  Integer $resume_rate = 20,
  Boolean $enable_x11_forwarding = true,
  Boolean $enable_scrontab = false,
  String  $config_addendum = '',
  Enum['quiet', 'fatal', 'error', 'info', 'verbose', 'debug', 'debug2', 'debug3', 'debug4', 'debug5'] $log_level = 'info',
)
{
  include epel
  include profile::base::powertools

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

  package { 'xauth':
    ensure => 'installed',
  }

  package { 'munge':
    ensure => 'installed',
  }

  # Sometime /var/run/munge is not created.
  # Munge RPM provides /usr/lib/tmpfiles.d/munge.conf
  # tmpfiles.d config was replaced with RuntimeDirectory as of munge 0.5.14
  # but we are stuck with 0.5.13 as upstream has not updated munge
  # since 2021. The next 2 file_lines make sure munge does not rely on
  # systemd-tmpfiles-setup.service.
  # Ref: https://github.com/dun/munge/commit/3eed37e3ca73c14b679394df7be151d27566b0fe
  # Ref: https://github.com/dun/munge/issues/75
  file_line { 'munge_runtimedirectory':
    path    => '/usr/lib/systemd/system/munge.service',
    match   => '^RuntimeDirectory=',
    line    => 'RuntimeDirectory=munge',
    after   => 'Group=munge',
    require => Package['munge'],
    notify  => Service['munge'],
  }

  file_line { 'munge_runtimedirectorymode':
    path    => '/usr/lib/systemd/system/munge.service',
    match   => '^RuntimeDirectoryMode=',
    line    => 'RuntimeDirectoryMode=0755',
    after   => 'Group=munge',
    require => Package['munge'],
    notify  => Service['munge'],
  }

  # Fix a warning in systemctl status munge about the location of the PID file.
  file_line { 'munge_pidfile':
    path    => '/usr/lib/systemd/system/munge.service',
    match   => '^PIDFile=',
    line    => 'PIDFile=/run/munge/munged.pid',
    require => Package['munge'],
    notify  => Service['munge'],
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

  file { '/etc/slurm/epilog':
    ensure => 'present',
    owner  => 'slurm',
    group  => 'slurm',
    source => 'puppet:///modules/profile/slurm/epilog',
    mode   => '0755'
  }

  $slurm_path = @(END)
  if ! [[ ":$PATH:" == *":/opt/software/slurm/bin:"* ]]; then
    export SLURM_HOME=/opt/software/slurm
    export PATH=$SLURM_HOME/bin:$PATH
    export MANPATH=$SLURM_HOME/share/man:$MANPATH
    export LD_LIBRARY_PATH=$SLURM_HOME/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
  fi
  |END

  file { '/etc/profile.d/z-02-slurm.sh':
    ensure  => 'present',
    content => $slurm_path,
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
    require => [
      Exec['enable_powertools'],
      Package['munge'],
      Yumrepo['slurm-copr-repo'],
      Yumrepo['epel'],
    ],
  }

  package { ['slurm-contribs', 'slurm-perlapi' ]:
    ensure  => 'installed',
    require => [
      Package['slurm'],
      Package['munge'],
      Yumrepo['slurm-copr-repo']],
  }

  # slurm-contribs command "seff" requires Sys/hostname.pm
  # which is not packaged by default with perl in RHEL >= 9.
  if versioncmp($facts['os']['release']['major'], '9') >= 0 {
    ensure_packages(['perl-Sys-Hostname'], { 'ensure' => 'installed' })
  }

  package { 'slurm-libpmi':
    ensure  => 'installed',
    require => [
      Package['slurm'],
      Package['munge'],
      Yumrepo['slurm-copr-repo']
    ],
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
        'enable_scrontab'       => $enable_scrontab,
        'nb_nodes'              => length($nodes),
        'suspend_exc_nodes'     => join($suspend_exc_nodes, ','),
        'resume_timeout'        => $resume_timeout,
        'resume_rate'           => $resume_rate,
        'suspend_time'          => $suspend_time,
        'suspend_rate'          => $suspend_rate,
        'memlimit'              => $os_reserved_memory,
        'partitions'            => $partitions,
        'slurmctl'              => profile::gethostnames_with_class('profile::slurm::controller'),
        'slurmdb'               => profile::gethostnames_with_class('profile::slurm::accounting'),
        'log_level'             => $log_level,
      }),
    group   => 'slurm',
    owner   => 'slurm',
    mode    => '0644',
    require => File['/etc/slurm'],
  }

  file { '/etc/slurm/slurm-addendum.conf':
    ensure  => present,
    content => @("EOF"),
      # FILE MANAGED BY PUPPET, DO NOT EDIT DIRECTLY.
      # Content of this file has been specified via profile::slurm::base::config_addendum.
      # It has not been validated.
      ${config_addendum}
      |EOF
    group   => 'slurm',
    owner   => 'slurm',
    mode    => '0644',
    require => File['/etc/slurm'],
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
        'weights'  => profile::slurm::compute_weights($nodes),
      }),
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
  include mysql::server
  include profile::slurm::base

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
    require => [
      Package['slurm'],
      Package['munge'],
      Yumrepo['slurm-copr-repo']
    ],
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

  @consul::service { 'slurmdbd':
    port => $dbd_port,
  }

  wait_for { 'slurmdbd_started':
    query             => 'cat /var/log/slurm/slurmdbd.log',
    regex             => '^\[[.:0-9\-T]{23}\] slurmdbd version \d+.\d+.\d+(-\d+){0,1}(rc\d+){0,1} started$',
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

  $instances = lookup('terraform.instances')
  $nodes = $instances.filter|$key, $attr| { 'node' in $attr['tags'] }
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

  file { '/usr/sbin/slurm_mail':
    ensure => 'present',
    source => 'puppet:///modules/profile/slurm/slurm_mail',
    mode   => '0755',
  }

  $autoscale_env_prefix = '/opt/software/slurm/autoscale_env'
  uv::venv { 'autoscale_slurm_env':
    prefix       => $autoscale_env_prefix,
    python       => '3.13',
    requirements => "https://github.com/MagicCastle/slurm-autoscale-tfe/releases/download/v${autoscale_version}/slurm_autoscale_tfe-${autoscale_version}-py3-none-any.whl",
    require      => [
      Package['slurm'],
    ],
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
    content => @("EOT"/$)
#!/bin/bash
{
  source /etc/slurm/env.secrets
  export PATH=\$PATH:/opt/software/slurm/bin
  ${autoscale_env_prefix}/bin/slurm_resume \$@
} &>> /var/log/slurm/slurm_autoscale.log
|EOT
  }

  file { '/usr/bin/slurm_resume_fail':
    ensure  => 'present',
    mode    => '0755',
    seltype => 'bin_t',
    content => @("EOT"/$)
#!/bin/bash
{
  source /etc/slurm/env.secrets
  export PATH=\$PATH:/opt/software/slurm/bin
  ${autoscale_env_prefix}/bin/slurm_resume_fail \$@
} &>> /var/log/slurm/slurm_autoscale.log
|EOT
  }


  file { '/usr/bin/slurm_suspend':
    ensure  => 'present',
    mode    => '0755',
    seltype => 'bin_t',
    content => @("EOT"/$)
#!/bin/bash
{
  source /etc/slurm/env.secrets
  export PATH=\$PATH:/opt/software/slurm/bin
  ${autoscale_env_prefix}/bin/slurm_suspend \$@
} &>> /var/log/slurm/slurm_autoscale.log
|EOT
  }


  file { '/etc/slurm/job_submit.lua':
    ensure  => 'present',
    owner   => 'slurm',
    group   => 'slurm',
    content => epp('profile/slurm/job_submit.lua',
      {
        'selinux_enabled' => $facts['os']['selinux']['enabled'],
        'selinux_context' => $selinux_context,
      }
    ),
  }

  @consul::service { 'slurmctld':
    port => 6817,
  }

  package { 'slurm-slurmctld':
    ensure  => 'installed',
    require => [
      Package['munge'],
      Package['slurm'],
    ],
  }

  service { 'slurmctld':
    ensure    => 'running',
    enable    => true,
    require   => [
      Package['slurm-slurmctld'],
    ],
    subscribe => [
      File['/etc/slurm/slurm.conf'],
      File['/etc/slurm/slurm-addendum.conf'],
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
class profile::slurm::node (
  Boolean $enable_tmpfs_mounts = true,
  Array[String] $pam_access_groups = ['wheel'],
) {
  contain profile::slurm::base

  package { ['slurm-slurmd', 'slurm-pam_slurm']:
    ensure  => 'installed',
    require => Package['slurm'],
  }

  if $enable_tmpfs_mounts {
    $slurm_version = lookup('profile::slurm::base::slurm_version')
    $cc_tmpfs_mounts_url = "https://download.copr.fedorainfracloud.org/results/cmdntrf/spank-cc-tmpfs_mounts-${slurm_version}/"

    yumrepo { 'spank-cc-tmpfs_mounts-copr-repo':
      enabled             => true,
      descr               => 'Copr repo for spank-cc-tmpfs_mounts owned by cmdntrf',
      baseurl             => "${cc_tmpfs_mounts_url}/epel-\$releasever-\$basearch/",
      skip_if_unavailable => true,
      gpgcheck            => 1,
      gpgkey              => "${cc_tmpfs_mounts_url}/pubkey.gpg",
      repo_gpgcheck       => 0,
    }
    package { 'spank-cc-tmpfs_mounts':
      ensure  => 'installed',
      require => [
        Package['slurm-slurmd'],
        Yumrepo['spank-cc-tmpfs_mounts-copr-repo'],
      ]
    }
    $plugstack = 'required /opt/software/slurm/lib64/slurm/cc-tmpfs_mounts.so bindself=/tmp bindself=/dev/shm target=/localscratch bind=/var/tmp/'
  } else {
    $plugstack = ''
  }

  file { '/etc/slurm/plugstack.conf':
    ensure  => 'present',
    owner   => 'slurm',
    group   => 'slurm',
    content => $plugstack,
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

  $access_conf = @(END)
# Allow root cronjob
+ : root : cron crond :0 tty1 tty2 tty3 tty4 tty5 tty6
# Allow other groups if any
<% $pam_access_groups.each | $group | { %>
+:<%= $group %>:ALL
<% } %>
-:ALL:ALL
|END

  file { '/etc/security/access.conf':
    ensure  => present,
    content => inline_epp($access_conf, { 'pam_access_groups' => $pam_access_groups }),
  }

  selinux::module { 'sshd_pam_slurm_adopt':
    ensure    => 'present',
    source_pp => 'puppet:///modules/profile/slurm/pam_slurm_adopt.pp',
  }

  selinux::module { 'slurmd':
    ensure    => 'present',
    source_pp => 'puppet:///modules/profile/slurm/slurmd.pp',
  }

  if !($facts['virtual'] =~ /^(container|lxc).*$/) {
    # Implementation of user limits as recommended in
    # https://cloud.google.com/architecture/best-practices-for-using-mpi-on-compute-engine
    # + some common values found on Compute Canada clusters
    limits::limits{'*/core':
      soft => '0',
      hard => 'unlimited'
    }

    limits::limits{'*/nproc':
      soft => '4096',
    }

    limits::limits{'root/nproc':
      soft => 'unlimited',
    }

    limits::limits{'*/memlock':
      both => 'unlimited',
    }

    limits::limits{'*/stack':
      both => 'unlimited',
    }

    limits::limits{'*/nofile':
      both => '1048576',
    }

    limits::limits{'*/cpu':
      both => 'unlimited',
    }

    limits::limits{'*/rtprio':
      both => 'unlimited',
    }
  }

  ensure_resource('file', '/localscratch', { 'ensure' => 'directory', 'seltype' => 'tmp_t' })
  if '/dev/disk/by-label/ephemeral0' in $facts['/dev/disk'] {
    mount { '/localscratch':
      ensure  => mounted,
      device  => '/mnt/ephemeral0',
      fstype  => none,
      options => 'rw,bind',
      require => [
        File['/localscratch'],
      ],
    }
  }

  file { '/var/spool/slurmd':
    ensure => 'directory',
    owner  => 'slurm',
    group  => 'slurm'
  }

  file { '/opt/software/slurm/bin/nvidia_gres.sh':
    source  => 'puppet:///modules/profile/slurm/nvidia_gres.sh',
    mode    => '0755',
    require => Package['slurm'],
  }

  if $facts['nvidia_gpu_count'] > 0 {
    file { '/etc/slurm/gres.conf':
      ensure => present,
    }
    exec { 'slurm-nvidia_gres':
      command   => '/opt/software/slurm/bin/nvidia_gres.sh > /etc/slurm/gres.conf',
      unless    => '/opt/software/slurm/bin/nvidia_gres.sh | cmp -s - /etc/slurm/gres.conf',
      notify    => Service['slurmd'],
      subscribe => [
        File['/opt/software/slurm/bin/nvidia_gres.sh'],
        File['/etc/slurm/gres.conf'],
      ]
    }
    Kmod::Load <| tag == profile::gpu  |> -> Exec['slurm-nvidia_gres']
    Exec <| tag == profile::gpu |> ~> Exec['slurm-nvidia_gres']
    Exec <| tag == profile::gpu::install::mig |> ~> Exec['slurm-nvidia_gres']
  }

  Exec <| tag == profile::cvmfs |> -> Service['slurmd']
  Exec <| tag == profile::freeipa |> -> Service['slurmd']
  Exec <| tag == profile::gpu |> -> Service['slurmd']
  Exec <| tag == profile::gpu::install::mig |> ~> Service['slurmd']
  Exec <| tag == profile::jupyterhub |> -> Service['slurmd']
  Kmod::Load <| |> -> Service['slurmd']
  Mount <| |> -> Service['slurmd']
  Selinux::Module <| |> -> Service['slurmd']
  Selinux::Exec_restorecon <| |> -> Service['slurmd']
  Selinux::Boolean <| |> -> Service['slurmd']
  Service <| tag == prometheus |> -> Service['slurmd']
  Service <| tag == profile::prometheus |> -> Service['slurmd']
  User <| |> -> Service['slurmd']
  Group <| |> -> Service['slurmd']
  Pam <| |> -> Service['slurmd']

  if $facts['virtual'] =~ /^(container|lxc).*$/ {
    # When running slurmd in containers, the reported boot time
    # corresponds to the host boot time. This leads slurmctld to
    # think the node has not properly booted when using
    # slurm powersaving / autoscaling function. By adding `-b`
    # option to slurmd, the reported boot time corresponds to the
    # time when slurmd started instead.
    # Ref: https://support.schedmd.com/show_bug.cgi?id=4039
    file { '/etc/sysconfig/slurmd':
      content => 'SLURMD_OPTIONS="-b"',
    }
  }

  service { 'slurmd':
    ensure    => 'running',
    enable    => false,
    subscribe => [
      File['/etc/slurm/cgroup.conf'],
      File['/etc/slurm/plugstack.conf'],
      File['/etc/slurm/slurm.conf'],
      File['/etc/slurm/slurm-addendum.conf'],
      File['/etc/slurm/nodes.conf'],
    ],
    require   => [
      Package['slurm-slurmd'],
    ],
  }

  # If the Slurm SuspendProgram has failed for any reason
  # during a node power off, it is possible that the node will
  # still be online, with slurmd running, but the controller will
  # ignore it until slurmd is restarted. This exec check if the
  # controller thinks the node is powered off or non responsive
  # and if it is the case, it restarts slurmd so the state in
  # in slurmctld can be properly refreshed.
  $hostname = $facts['networking']['hostname']
  exec { 'slurmd_state_invalid_restart':
    command => 'systemctl restart slurmd',
    onlyif  => "test $(sinfo -h --states=no_respond,powered_down -o %n -n ${hostname} | wc -l) -eq 1",
    path    => ['/usr/bin', '/opt/software/slurm/bin'],
    require => Service['slurmd'],
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
}

# Slurm submitter class. This is for instances that neither run slurmd
# and slurmctld but still need to be able to communicate with the slurm
# controller through Slurm command-line tools.
class profile::slurm::submitter {
  contain profile::slurm::base
}
