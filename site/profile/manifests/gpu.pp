class profile::gpu {

  $driver_ver = $::facts['nvidia_driver_version']
  if ! $facts['nvidia_grid_vgpu'] {
    $cuda_ver = $::facts['nvidia_cuda_version']
    $os = "rhel${::facts['os']['release']['major']}"
    $arch = $::facts['os']['architecture']
    $repo_name = "cuda-repo-${os}"
    package { 'cuda-repo':
      ensure   => 'installed',
      provider => 'rpm',
      name     => $repo_name,
      source   => "http://developer.download.nvidia.com/compute/cuda/repos/${os}/${arch}/${repo_name}-${cuda_ver}.${arch}.rpm"
    }

    package { [
      'nvidia-driver-latest-dkms',
      'nvidia-driver-latest-dkms-cuda',
      'nvidia-driver-latest-dkms-cuda-libs',
      'nvidia-driver-latest-dkms-devel',
      'nvidia-driver-latest-dkms-libs',
      'nvidia-driver-latest-dkms-NvFBCOpenGL',
      'nvidia-driver-latest-dkms-NVML',
      'nvidia-modprobe-latest-dkms',
      'nvidia-persistenced-latest-dkms',
      'nvidia-xconfig-latest-dkms',
      'kmod-nvidia-latest-dkms',
      ]:
      ensure  => 'installed',
      require => Package['cuda-repo']
    }
    $dkms_requirements = [Package['kernel-devel'], Package['kmod-nvidia-latest-dkms']]
  } else {
    service { 'nvidia-gridd':
      ensure => 'running',
      enable => true,
    }
    $dkms_requirements = [Package['kernel-devel']]
  }

  if $facts['nvidia_gpu_count'] > 0 {
    ensure_packages(['kernel-devel'], {ensure => 'installed'})

    exec { 'dkms autoinstall':
      path    => ['/usr/bin', '/usr/sbin'],
      onlyif  => 'dkms status | grep -v -q \'nvidia.*installed\'',
      timeout => 0,
      require => $dkms_requirements,
    }

    kmod::load { [
      'nvidia',
      'nvidia_drm',
      'nvidia_modeset',
      'nvidia_uvm'
      ]:
      require => Exec['dkms autoinstall']
    }

    if ! $facts['nvidia_grid_vgpu'] {
      file { '/var/run/nvidia-persistenced':
        ensure => directory,
        owner  => 'nvidia-persistenced',
        group  => 'nvidia-persistenced',
        mode   => '0755',
      }

      augeas { 'nvidia-persistenced.service':
        context => '/files/lib/systemd/system/nvidia-persistenced.service/Service',
        changes => [
          'set User/value nvidia-persistenced',
          'set Group/value nvidia-persistenced',
          'rm ExecStart/arguments',
        ],
      }

      service { 'nvidia-persistenced':
        ensure  => 'running',
        enable  => true,
        require => [
          File['/var/run/nvidia-persistenced'],
          Augeas['nvidia-persistenced.service'],
        ],
      }
    }
  }

  file { '/usr/lib64/nvidia':
    ensure => directory
  }

  $nvidia_libs = [
    "libnvidia-ml.so.${driver_ver}", 'libnvidia-ml.so.1', 'libnvidia-fbc.so.1',
    "libnvidia-fbc.so.${driver_ver}", 'libnvidia-ifr.so.1', "libnvidia-ifr.so.${driver_ver}",
    'libcuda.so', 'libcuda.so.1', "libcuda.so.${driver_ver}", "libnvcuvid.so.${driver_ver}",
    'libnvcuvid.so.1', "libnvidia-compiler.so.${driver_ver}", 'libnvidia-encode.so.1',
    "libnvidia-encode.so.${driver_ver}", "libnvidia-fatbinaryloader.so.${driver_ver}",
    'libnvidia-opencl.so.1', "libnvidia-opencl.so.${driver_ver}", 'libnvidia-opticalflow.so.1',
    "libnvidia-opticalflow.so.${driver_ver}", 'libnvidia-ptxjitcompiler.so.1', "libnvidia-ptxjitcompiler.so.${driver_ver}",
    'libnvcuvid.so', 'libnvidia-cfg.so', 'libnvidia-encode.so',
    'libnvidia-fbc.so', 'libnvidia-ifr.so', 'libnvidia-ml.so',
    'libnvidia-ptxjitcompiler.so', 'libEGL_nvidia.so.0', "libEGL_nvidia.so.${driver_ver}",
    'libGLESv1_CM_nvidia.so.1', "libGLESv1_CM_nvidia.so.${driver_ver}", 'libGLESv2_nvidia.so.2',
    "libGLESv2_nvidia.so.${driver_ver}", 'libGLX_indirect.so.0', 'libGLX_nvidia.so.0',
    "libGLX_nvidia.so.${driver_ver}", "libnvidia-cbl.so.${driver_ver}", 'libnvidia-cfg.so.1',
    "libnvidia-cfg.so.${driver_ver}", "libnvidia-eglcore.so.${driver_ver}", "libnvidia-glcore.so.${driver_ver}",
    "libnvidia-glsi.so.${driver_ver}", "libnvidia-glvkspirv.so.${driver_ver}", "libnvidia-rtcore.so.${driver_ver}",
    "libnvidia-tls.so.${driver_ver}", 'libnvoptix.so.1', "libnvoptix.so.${driver_ver}"]

  $nvidia_libs.each |String $lib| {
    file { "/usr/lib64/nvidia/${lib}":
      ensure  => link,
      target  => "/usr/lib64/${lib}",
      seltype => 'lib_t'
    }
  }

}
