class profile::gpu {
  if $facts['nvidia_gpu_count'] > 0 {
    require profile::gpu::install
    if ! $facts['nvidia_grid_vgpu'] {
      service { 'nvidia-persistenced':
        ensure => 'running',
        enable => true,
      }
    } else {
      service { 'nvidia-gridd':
        ensure => 'running',
        enable => true,
      }
    }
  }
}

class profile::gpu::install {
  ensure_resource('file', '/etc/nvidia', {'ensure' => 'directory' })

  if ! $facts['nvidia_grid_vgpu'] {
    require profile::gpu::install::passthrough
  } else {
    require profile::gpu::install::vgpu
  }

  ensure_packages(['kernel-devel'], {ensure => 'installed'})
  ensure_packages(['dkms'], {
    'require' => Yumrepo['epel']
  })

  exec { 'dkms autoinstall':
    path    => ['/usr/bin', '/usr/sbin'],
    onlyif  => 'dkms status | grep -v -q \'nvidia.*installed\'',
    timeout => 0,
    require => [
      Package['kernel-devel'],
      Package['dkms']
    ]
  }

  kmod::load { [
    'nvidia',
    'nvidia_drm',
    'nvidia_modeset',
    'nvidia_uvm'
    ]:
    require => Exec['dkms autoinstall']
  }

  file { '/usr/lib64/nvidia':
    ensure => directory
  }

  $driver_ver = $::facts['nvidia_driver_version']
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

class profile::gpu::install::passthrough(Array[String] $packages) {
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

  package { $packages:
    ensure  => 'installed',
    require => [Package['cuda-repo'], Package['dkms']]
  }

  -> file { '/var/run/nvidia-persistenced':
    ensure => directory,
    owner  => 'nvidia-persistenced',
    group  => 'nvidia-persistenced',
    mode   => '0755',
  }

  -> augeas { 'nvidia-persistenced.service':
    context => '/files/lib/systemd/system/nvidia-persistenced.service/Service',
    changes => [
      'set User/value nvidia-persistenced',
      'set Group/value nvidia-persistenced',
      'rm ExecStart/arguments',
    ],
  }
}

class profile::gpu::install::vgpu(
  Enum['rpm', 'bin', 'none'] $installer = 'none',
)
{
  if $installer == 'rpm' {
    include profile::gpu::install::vgpu::rpm
  } elsif $installer == 'bin' {
    # install from binary installer
    include profile::gpu::install::vgpu::bin
  }
}

class profile::gpu::install::vgpu::rpm(
  String $source,
  Array[String] $packages,
)
{
    $source_pkg_name = split(split($source, '[/]')[-1], '[.]')[0]
    package { 'vgpu-repo':
      ensure   => 'latest',
      provider => 'rpm',
      name     => $source_pkg_name,
      source   => $source,
    }

    package { $packages:
      ensure  => 'installed',
      require => [
        Yumrepo['epel'],
        Package['vgpu-repo'],
      ]
    }

    # The device files/dev/nvidia* are normally created by nvidia-modprobe
    # If the permissions of nvidia-modprobe exclude setuid, some device files
    # will be missing.
    # https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#runfile-verifications
    -> file { '/usr/bin/nvidia-modprobe':
      ensure => present,
      mode   => '4755',
      owner  => 'root',
      group  => 'root',
    }
}

class profile::gpu::install::vgpu::bin(
  String $source,
  String $gridd_source,
)
{
  exec { 'vgpu-driver-install-bin':
    command => "curl -L ${source} -o /tmp/NVIDIA-driver.run && sh /tmp/NVIDIA-driver.run --ui=none --no-questions --disable-nouveau && rm /tmp/NVIDIA-driver.run",
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    creates => [
      '/usr/bin/nvidia-smi',
      '/usr/bin/nvidia-modprobe',
    ],
    timeout => 300,
  }

  file { '/etc/nvidia/gridd.conf':
    ensure => present,
    mode   => '0644',
    owner  => 'root',
    group  => 'root',
    source => $gridd_source,
  }
}
