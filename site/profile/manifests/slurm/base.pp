# Slurm base class that is included in each different profile.
# The class configures the slurm and munge users, install the
# base slurm packages and configures everything that is required
# on all types of nodes.
# @param cluster_name Specifies the name of the cluster as it appears in slurm.conf
# @param munge_key Specifies the munge secret key that allows slurm nodes to communicate
# @param slurm_version Specifies which version of Slurm to install
# @param os_reserved_memory Specifies the amount of memory reserved for the operating system in compute node
# @param force_slurm_in_path Specifies if the slurm binaries should be in the path of every user regardless of their UID
# @param enable_x11_forwarding Specifies if X11 forwarding should be enabled
class profile::slurm::base (
  String $cluster_name,
  String $munge_key,
  Enum['19.05', '20.11', '21.08'] $slurm_version,
  Integer $os_reserved_memory,
  Boolean $force_slurm_in_path = false,
  Boolean $enable_x11_forwarding = true,
) {
  group { 'slurm':
    ensure => 'present',
    gid    => '2001',
  }

  user { 'slurm':
    ensure  => 'present',
    groups  => 'slurm',
    uid     => '2001',
    home    => '/var/lib/slurm',
    comment => 'Slurm workload manager',
    shell   => '/bin/bash',
    before  => Package['slurm'],
  }

  group { 'munge':
    ensure => 'present',
    gid    => '2002',
  }

  user { 'munge':
    ensure  => 'present',
    groups  => 'munge',
    uid     => '2002',
    home    => '/var/lib/munge',
    comment => 'MUNGE Uid N Gid Emporium',
    shell   => '/sbin/nologin',
    before  => Package['munge'],
  }

  package { 'munge':
    ensure  => 'installed',
    require => Yumrepo['epel'],
  }

  file { '/var/log/slurm':
    ensure => 'directory',
    owner  => 'slurm',
    group  => 'slurm',
  }

  file { '/var/spool/slurm':
    ensure => 'directory',
    owner  => 'slurm',
    group  => 'slurm',
  }

  file { '/etc/slurm':
    ensure  => 'directory',
    owner   => 'slurm',
    group   => 'slurm',
    seltype => 'usr_t',
  }

  file { '/etc/munge':
    ensure => 'directory',
    owner  => 'munge',
    group  => 'munge',
  }

  file { '/etc/slurm/cgroup.conf':
    owner   => 'slurm',
    group   => 'slurm',
    content => epp('profile/slurm/cgroup.conf',
      {
        'slurm_version' => $slurm_version,
      }
    ),
  }

  file { '/etc/slurm/cgroup_allowed_devices_file.conf':
    owner  => 'slurm',
    group  => 'slurm',
    source => 'puppet:///modules/profile/slurm/cgroup_allowed_devices_file.conf',
  }

  file { '/etc/slurm/epilog':
    owner  => 'slurm',
    group  => 'slurm',
    source => 'puppet:///modules/profile/slurm/epilog',
    mode   => '0755',
  }

  file { '/etc/slurm/node.conf.tpl':
    owner   => 'slurm',
    group   => 'slurm',
    content => "{{ service \"slurmd\" | toJSON | plugin \"/usr/local/bin/consul2slurm\" }}\n",
    seltype => 'etc_t',
    notify  => Service['consul-template'],
  }

  file { '/etc/profile.d/z-00-slurm.sh':
    content => epp('profile/slurm/z-00-slurm.sh',
      {
        'force_slurm_in_path' => $force_slurm_in_path,
        'uid_max'             => $facts['uid_max'],
      }
    ),
  }

  file { '/etc/munge/munge.key':
    owner   => 'munge',
    group   => 'munge',
    mode    => '0400',
    content => $munge_key,
    before  => Service['munge'],
  }

  service { 'munge':
    ensure    => 'running',
    enable    => true,
    subscribe => File['/etc/munge/munge.key'],
    require   => Package['munge'],
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
    require => [
      Package['munge'],
      Yumrepo['slurm-copr-repo']
    ],
  }

  package { ['slurm-contribs', 'slurm-perlapi']:
    ensure  => 'installed',
    require => [
      Package['munge'],
      Yumrepo['slurm-copr-repo']
    ],
  }

  package { 'slurm-libpmi':
    ensure  => 'installed',
    require => [
      Package['munge'],
      Yumrepo['slurm-copr-repo']
    ],
  }

  file { 'slurm.conf.tpl':
    path    => '/etc/slurm/slurm.conf.tpl',
    content => epp('profile/slurm/slurm.conf',
      {
        'cluster_name'          => $cluster_name,
        'slurm_version'         => $slurm_version,
        'enable_x11_forwarding' => $enable_x11_forwarding,
      }
    ),
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

  # SELinux policy required to allow confined users to submit job with Slurm 19, 20, 21.
  # Slurm commands tries to write to a socket in /var/run/munge.
  # Confined users cannot stat this file, neither write to it. The policy
  # allows user_t to getattr and write var_run_t sock file.
  # To get the policy, we had to disable dontaudit rules with : sudo semanage -DB
  selinux::module { 'munge_socket':
    ensure    => 'present',
    source_pp => 'puppet:///modules/profile/slurm/munge_socket.pp',
  }
}
