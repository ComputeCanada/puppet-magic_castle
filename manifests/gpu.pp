class profile::gpu {
  package { 'cuda-repo':
    ensure   => 'installed',
    provider => 'rpm',
    name     => 'cuda-repo-rhel7',
    source   => 'http://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/cuda-repo-rhel7-10.1.168-1.x86_64.rpm'
  }

  package { [
    'nvidia-driver-cuda-libs',
    'nvidia-driver-NVML',
    'nvidia-driver-NvFBCOpenGL',
    'nvidia-driver-libs',
    'dkms-nvidia',
    'nvidia-driver',
    'nvidia-driver-cuda',
    'nvidia-driver-devel',
    'nvidia-modprobe',
    ]:
    ensure  => 'installed',
    require => Package['cuda-repo']
  }
}
