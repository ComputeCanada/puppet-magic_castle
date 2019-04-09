class profile::gpu {
  file_line { 'kmod_nvidia_exclude':
    ensure => present,
    path   => '/etc/yum.conf',
    line   => 'exclude=nvidia-x11*',
  }

  class { 'yum':
    config_options => {
        obsoletes => false
      },
    }

  package { 'cuda-repo':
    ensure   => 'installed',
    provider => 'rpm',
    name     => 'cuda-repo-rhel7',
    source   => 'http://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/cuda-repo-rhel7-10.0.130-1.x86_64.rpm'
  }

  package { ['nvidia-kmod-396.26', 'xorg-x11-drv-nvidia-396.26', 'xorg-x11-drv-nvidia-devel-396.26', 'cuda-drivers-396.26']:
    ensure  => 'installed',
    require => [Class['yum'], File_line['kmod_nvidia_exclude'], Package['cuda-repo']]
  }
}
