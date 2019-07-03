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

  file { '/usr/lib64/nvidia':
    ensure => directory
  }

  $cuda_ver = '418.67'
  $nvidia_libs = [
    "libnvidia-ml.so.${cuda_ver}", 'libnvidia-ml.so.1', 'libnvidia-fbc.so.1',
    "libnvidia-fbc.so.${cuda_ver}", 'libnvidia-ifr.so.1', "libnvidia-ifr.so.${cuda_ver}",
    'libcuda.so', 'libcuda.so.1', "libcuda.so.${cuda_ver}", "libnvcuvid.so.${cuda_ver}",
    'libnvcuvid.so.1', "libnvidia-compiler.so.${cuda_ver}", 'libnvidia-encode.so.1',
    "libnvidia-encode.so.${cuda_ver}", "libnvidia-fatbinaryloader.so.${cuda_ver}",
    'libnvidia-opencl.so.1', "libnvidia-opencl.so.${cuda_ver}", 'libnvidia-opticalflow.so.1',
    "libnvidia-opticalflow.so.${cuda_ver}", 'libnvidia-ptxjitcompiler.so.1', "libnvidia-ptxjitcompiler.so.${cuda_ver}",
    'libnvcuvid.so', 'libnvidia-cfg.so', 'libnvidia-encode.so',
    'libnvidia-fbc.so', 'libnvidia-ifr.so', 'libnvidia-ml.so',
    'libnvidia-ptxjitcompiler.so', 'libEGL_nvidia.so.0', "libEGL_nvidia.so.${cuda_ver}",
    'libGLESv1_CM_nvidia.so.1', "libGLESv1_CM_nvidia.so.${cuda_ver}", 'libGLESv2_nvidia.so.2',
    "libGLESv2_nvidia.so.${cuda_ver}", 'libGLX_indirect.so.0', 'libGLX_nvidia.so.0',
    "libGLX_nvidia.so.${cuda_ver}", "libnvidia-cbl.so.${cuda_ver}", 'libnvidia-cfg.so.1',
    "libnvidia-cfg.so.${cuda_ver}", "libnvidia-eglcore.so.${cuda_ver}", "libnvidia-glcore.so.${cuda_ver}",
    "libnvidia-glsi.so.${cuda_ver}", "libnvidia-glvkspirv.so.${cuda_ver}", "libnvidia-rtcore.so.${cuda_ver}",
    "libnvidia-tls.so.${cuda_ver}", 'libnvoptix.so.1', "libnvoptix.so.${cuda_ver}"]

  $nvidia_libs.each |String $lib| {
    file { "/usr/lib64/nvidia/${lib}":
      ensure => link,
      target => "/usr/lib64/${lib}",
    }
  }
}
