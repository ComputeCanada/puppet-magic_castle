class profile::gpu {
  if $facts['nvidia_gpu_count'] > 0 {
    require profile::gpu::install
    if ! $facts['nvidia_grid_vgpu'] {
      service { 'nvidia-persistenced':
        ensure => 'running',
        enable => true,
      }
      service { 'nvidia-dcgm':
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
  ensure_resource('file', '/etc/nvidia', { 'ensure' => 'directory' })
  ensure_packages(['kernel-devel'], { 'ensure' => 'installed' })
  ensure_packages(['dkms'], { 'require' => Yumrepo['epel'] })

  selinux::module { 'nvidia-gpu':
    ensure    => 'present',
    source_pp => 'puppet:///modules/profile/gpu/nvidia-gpu.pp',
  }

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
        Package['dkms'],
      ],
    }
    $kmod_require = [Exec['dkms autoinstall']]
  } else {
    $kmod_require = []
  }

  kmod::load { [
      'nvidia',
      'nvidia_drm',
      'nvidia_modeset',
      'nvidia_uvm',
    ]:
      require => $kmod_require,
  }

  if $lib_symlink_path {
    $lib_symlink_path_split = split($lib_symlink_path, '/')
    $lib_symlink_dir = Hash(
      $lib_symlink_path_split[1,-1].map |Integer $index, String $value| {
        [join($lib_symlink_path_split[0, $index+2], '/'), { 'ensure' => 'directory', 'notify' => Exec['nvidia-symlink'] }]
      }.filter |$array| {
        !($array[0] in ['/lib', '/lib64', '/usr', '/usr/lib', '/usr/lib64', '/opt'])
      }
    )
    $lib_symlink_dir_res = ensure_resources('file', $lib_symlink_dir)
    exec { 'nvidia-symlink':
      command     => "rpm -qa *nvidia* | xargs rpm -ql | grep -P '/usr/lib64/[a-z0-9-.]*.so[0-9.]*' | xargs -I {} ln -sf {} ${lib_symlink_path}", # lint:ignore:140chars
      refreshonly => true,
      path        => ['/bin', '/usr/bin'],
    }
  }
}

class profile::gpu::install::passthrough (
  Array[String] $packages,
) {
  $os = "rhel${::facts['os']['release']['major']}"
  $arch = $::facts['os']['architecture']
  if versioncmp($::facts['os']['release']['major'], '8') >= 0 {
    $repo_config_cmd = 'dnf config-manager'
  } else {
    $repo_config_cmd = 'yum-config-manager'
  }

  exec { 'cuda-repo':
    command => "${repo_config_cmd} --add-repo http://developer.download.nvidia.com/compute/cuda/repos/${os}/${arch}/cuda-${os}.repo",
    creates => "/etc/yum.repos.d/cuda-${os}.repo",
    path    => ['/usr/bin'],
  }

  $mig_profile = lookup("terraform.instances.${facts['networking']['hostname']}.specs.mig")
  if $mig_profile {
    include profile::gpu::install::mig
  }

  package { $packages:
    ensure  => 'installed',
    require => [
      Exec['cuda-repo'],
      Yumrepo['epel'],
    ],
    notify  => Exec['nvidia-symlink'],
  }

  # Used by slurm-job-exporter to export GPU metrics
  -> package { 'datacenter-gpu-manager': }

  -> file { '/run/nvidia-persistenced':
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

  file { '/usr/lib/tmpfiles.d/nvidia-persistenced.conf':
    content => 'd /run/nvidia-persistenced 0755 nvidia-persistenced nvidia-persistenced -',
    mode    => '0644',
  }
}

class profile::gpu::install::mig (
  String $mig_manager_version = '0.5.5',
) {
  $mig_profile = lookup("terraform.instances.${facts['networking']['hostname']}.specs.mig")

  package { 'nvidia-mig-manager':
    ensure   => 'latest',
    provider => 'rpm',
    name     => 'nvidia-mig-manager',
    source   => "https://github.com/NVIDIA/mig-parted/releases/download/v${$mig_manager_version}/nvidia-mig-manager-${mig_manager_version}-1.${arch}.rpm",
  }

  service { 'nvidia-mig-manager':
    ensure  => stopped,
    enable  => false,
    require => Package['nvidia-mig-manager'],
  }

  file { '/etc/nvidia-mig-manager/puppet-config.yaml':
    require => Package['nvidia-mig-manager'],
    content => @("EOT")
      version: v1
      mig-configs:
        default:
          - devices: all
            mig-enabled: true
            mig-devices: ${to_json($mig_profile)}
      |EOT
  }

  file { '/etc/nvidia-mig-manager/puppet-hooks.yaml':
    require => Package['nvidia-mig-manager'],
    content => @("EOT")
      version: v1
      hooks:
        pre-apply-mode:
        - workdir: "/etc/nvidia-mig-manager"
          command: "/bin/bash"
          args: ["-x", "-c", "source hooks.sh; stop_driver_services"]
        - workdir: "/etc/nvidia-mig-manager"
          command: "/bin/sh"
          args: ["-c", "systemctl -q is-active slurmd && systemctl stop slurmd || true"]
        apply-exit:
        - workdir: "/etc/nvidia-mig-manager"
          command: "/bin/bash"
          args: ["-x", "-c", "source hooks.sh; start_driver_services"]
      |EOT
  }

  exec { 'nvidia-mig-parted apply':
    unless      => 'nvidia-mig-parted assert',
    require     => [
      Package['nvidia-mig-manager'],
      File['/etc/nvidia-mig-manager/puppet-config.yaml'],
      File['/etc/nvidia-mig-manager/puppet-hooks.yaml'],
    ],
    environment => [
      'MIG_PARTED_CONFIG_FILE=/etc/nvidia-mig-manager/puppet-config.yaml',
      'MIG_PARTED_HOOKS_FILE=/etc/nvidia-mig-manager/puppet-hooks.yaml',
      'MIG_PARTED_SELECTED_CONFIG=default',
      'MIG_PARTED_SKIP_RESET=false',
    ],
    path        => ['/usr/bin'],
  }

  Package <| tag == profile::gpu::install::passthrough |> -> Exec['nvidia-mig-parted apply']
}

class profile::gpu::install::vgpu (
  Enum['rpm', 'bin', 'none'] $installer = 'none',
  String $nvidia_ml_py_version = '11.515.75',
) {
  if $installer == 'rpm' {
    include profile::gpu::install::vgpu::rpm
  } elsif $installer == 'bin' {
    # install from binary installer
    include profile::gpu::install::vgpu::bin
  }

  # Used by slurm-job-exporter to export GPU metrics
  # DCGM does not work with GRID VGPU, most of the stats are missing
  ensure_packages(['python3'], { ensure => 'present' })
  $py3_version = lookup('os::redhat::python3::version')

  exec { 'pip install nvidia-ml-py':
    command => "/usr/bin/pip${py3_version} install --force-reinstall nvidia-ml-py==${nvidia_ml_py_version}",
    creates => "/usr/local/lib/python${py3_version}/site-packages/pynvml.py",
    before  => Service['slurm-job-exporter'],
    require => Package['python3'],
  }
}

class profile::gpu::install::vgpu::rpm (
  String $source,
  Array[String] $packages,
) {
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
    ],
    notify  => Exec['nvidia-symlink'],
  }

  # The device files/dev/nvidia* are normally created by nvidia-modprobe
  # If the permissions of nvidia-modprobe exclude setuid, some device files
  # will be missing.
  # https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#runfile-verifications
  -> file { '/usr/bin/nvidia-modprobe':
    ensure => file,
    mode   => '4755',
    owner  => 'root',
    group  => 'root',
  }
}

class profile::gpu::install::vgpu::bin (
  String $source,
  String $gridd_source,
) {
  exec { 'vgpu-driver-install-bin':
    command => "curl -L ${source} -o /tmp/NVIDIA-driver.run && sh /tmp/NVIDIA-driver.run --ui=none --no-questions --disable-nouveau && rm /tmp/NVIDIA-driver.run", # lint:ignore:140chars
    path    => ['/bin', '/usr/bin', '/sbin','/usr/sbin'],
    creates => [
      '/usr/bin/nvidia-smi',
      '/usr/bin/nvidia-modprobe',
    ],
    timeout => 300,
    require => [
      Package['kernel-devel'],
      Package['dkms'],
    ],
  }

  file { '/etc/nvidia/gridd.conf':
    ensure => file,
    mode   => '0644',
    owner  => 'root',
    group  => 'root',
    source => $gridd_source,
  }
}
