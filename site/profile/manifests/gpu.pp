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

class profile::gpu::install (
  String $lib_symlink_path = undef
) {
  ensure_resource('file', '/etc/nvidia', {'ensure' => 'directory' })
  ensure_packages(['kernel-devel'], {ensure => 'installed'})
  ensure_packages(['dkms'], {
    'require' => Yumrepo['epel']
  })

  if ! $facts['nvidia_grid_vgpu'] {
    require profile::gpu::install::passthrough
  } else {
    require profile::gpu::install::vgpu
  }

  # Binary installer do not build drivers with DKMS
  $installer = lookup('profile::gpu::install::vgpu::installer', undef, undef, '')
  if ! $facts['nvidia_grid_vgpu'] or $installer != 'bin' {
    exec { 'dkms autoinstall':
      path    => ['/usr/bin', '/usr/sbin'],
      onlyif  => 'dkms status | grep -v -q \'nvidia.*installed\'',
      timeout => 0,
      require => [
        Package['kernel-devel'],
        Package['dkms']
      ]
    }
    $kmod_require = [Exec['dkms autoinstall']]
  } else {
    $kmod_require = []
  }

  kmod::load { [
    'nvidia',
    'nvidia_drm',
    'nvidia_modeset',
    'nvidia_uvm'
    ]:
    require => $kmod_require
  }
  if $lib_symlink_path {
    $lib_symlink_path_split = split($lib_symlink_path, '/')
    $lib_symlink_path_split[1,-1].each |Integer $index, String $value| {
      ensure_resource('file', join($lib_symlink_path_split[0, $index+2], '/'), {'ensure' => 'directory'})
    }

    $nvidia_libs = [
      'libcuda.so.1',
      'libcuda.so',
      'libEGL_nvidia.so.0',
      'libGLESv1_CM_nvidia.so.1',
      'libGLESv2_nvidia.so.2',
      'libGLX_indirect.so.0',
      'libGLX_nvidia.so.0',
      'libnvcuvid.so.1',
      'libnvcuvid.so',
      'libnvidia-cfg.so.1',
      'libnvidia-cfg.so',
      'libnvidia-encode.so.1',
      'libnvidia-encode.so',
      'libnvidia-fbc.so.1',
      'libnvidia-fbc.so',
      'libnvidia-ifr.so.1',
      'libnvidia-ifr.so',
      'libnvidia-ml.so.1',
      'libnvidia-ml.so',
      'libnvidia-opencl.so.1',
      'libnvidia-opticalflow.so.1',
      'libnvidia-ptxjitcompiler.so.1',
      'libnvidia-ptxjitcompiler.so',
      'libnvoptix.so.1',
    ]

    $nvidia_libs.each |String $lib| {
      file { "${lib_symlink_path}/${lib}":
        ensure  => link,
        target  => "/usr/lib64/${lib}",
        seltype => 'lib_t'
      }
    }

    # WARNING : since the fact is computed before Puppet agent run,
    # on a clean host, the  symbolic links to the NVIDIA libraries
    # that include the version number will be created on the
    # second Puppet run only.
    $driver_vers = $::facts['nvidia_driver_version']
    if $driver_vers != '' {
      $nvidia_libs_vers = [
        "libcuda.so.${driver_vers}",
        "libEGL_nvidia.so.${driver_vers}",
        "libGLESv1_CM_nvidia.so.${driver_vers}",
        "libGLESv2_nvidia.so.${driver_vers}",
        "libGLX_nvidia.so.${driver_vers}",
        "libnvcuvid.so.${driver_vers}",
        "libnvidia-cbl.so.${driver_vers}",
        "libnvidia-cfg.so.${driver_vers}",
        "libnvidia-compiler.so.${driver_vers}",
        "libnvidia-eglcore.so.${driver_vers}",
        "libnvidia-encode.so.${driver_vers}",
        "libnvidia-fatbinaryloader.so.${driver_vers}",
        "libnvidia-fbc.so.${driver_vers}",
        "libnvidia-glcore.so.${driver_vers}",
        "libnvidia-glsi.so.${driver_vers}",
        "libnvidia-glvkspirv.so.${driver_vers}",
        "libnvidia-ifr.so.${driver_vers}",
        "libnvidia-ml.so.${driver_vers}",
        "libnvidia-opencl.so.${driver_vers}",
        "libnvidia-opticalflow.so.${driver_vers}",
        "libnvidia-ptxjitcompiler.so.${driver_vers}",
        "libnvidia-rtcore.so.${driver_vers}",
        "libnvidia-tls.so.${driver_vers}",
        "libnvoptix.so.${driver_vers}"
      ]

      $nvidia_libs_vers.each |String $lib| {
        file { "${lib_symlink_path}/${lib}":
          ensure  => link,
          target  => "/usr/lib64/${lib}",
          seltype => 'lib_t'
        }
      }
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
    require => [
      Package['cuda-repo'],
      Yumrepo['epel'],
    ],
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
    require => [
      Package['kernel-devel'],
      Package['dkms'],
    ]
  }

  file { '/etc/nvidia/gridd.conf':
    ensure => present,
    mode   => '0644',
    owner  => 'root',
    group  => 'root',
    source => $gridd_source,
  }
}
