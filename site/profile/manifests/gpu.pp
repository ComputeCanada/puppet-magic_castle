class profile::gpu (
  Boolean $restrict_profiling,
) {
  if $facts['nvidia_gpu_count'] > 0 {
    include profile::gpu::install
    include profile::gpu::services
  }
}

class profile::gpu::install (
  Optional[String] $lib_symlink_path = undef
) {
  $restrict_profiling = lookup('profile::gpu::restrict_profiling')
  ensure_resource('file', '/etc/nvidia', { 'ensure' => 'directory' })
  ensure_packages(['kernel-devel'], { 'name' => "kernel-devel-${facts['kernelrelease']}" })
  ensure_packages(['kernel-headers'], { 'name' => "kernel-headers-${facts['kernelrelease']}" })
  ensure_packages(['dkms'], { 'require' => [Package['kernel-devel'], Yumrepo['epel']] })
  $nvidia_kmod = ['nvidia', 'nvidia_modeset', 'nvidia_drm', 'nvidia_uvm']

  selinux::module { 'nvidia-gpu':
    ensure    => 'present',
    source_pp => 'puppet:///modules/profile/gpu/nvidia-gpu.pp',
  }

  file { '/etc/modprobe.d/nvidia.conf':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file_line { 'nvidia_restrict_profiling':
    path    => '/etc/modprobe.d/nvidia.conf',
    match   => '^options nvidia NVreg_RestrictProfilingToAdminUsers',
    line    => "options nvidia NVreg_RestrictProfilingToAdminUsers=${Integer($restrict_profiling)}",
    require => File['/etc/modprobe.d/nvidia.conf'],
    notify  => [
      Exec['stop_nvidia_services'],
      Exec['unload_nvidia_drivers'],
    ],
  }

  exec { 'unload_nvidia_drivers':
    command     => sprintf('rmmod %s', $nvidia_kmod.reverse.join(' ')),
    onlyif      => 'grep -qE "^nvidia " /proc/modules',
    refreshonly => true,
    require     => Exec['stop_nvidia_services'],
    notify      => Kmod::Load[$nvidia_kmod],
    path        => ['/bin', '/sbin'],
  }

  if ! profile::is_grid_vgpu() {
    include profile::gpu::install::passthrough
    Class['profile::gpu::install::passthrough'] -> Exec['dkms_nvidia']
  } else {
    include profile::gpu::install::vgpu
  }

  # Binary installer do not build drivers with DKMS
  $installer = lookup('profile::gpu::install::vgpu::installer', undef, undef, '')
  if ! profile::is_grid_vgpu() or $installer != 'bin' {
    exec { 'dkms_nvidia':
      command => "dkms autoinstall -m nvidia -k ${facts['kernelrelease']}",
      path    => ['/usr/bin', '/usr/sbin'],
      onlyif  => "dkms status -m nvidia -k ${facts['kernelrelease']} | grep -v -q installed",
      timeout => 0,
      before  => Kmod::Load[$nvidia_kmod],
      require => [
        Package['kernel-devel'],
        Package['dkms'],
      ],
    }
  }

  kmod::load { $nvidia_kmod: }

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

    Package<| tag == profile::gpu::install |> ~> Exec['nvidia-symlink']
    Exec<| tag == profile::gpu::install::vgpu::bin |> ~> Exec['nvidia-symlink']
  }
  Kmod::Load[$nvidia_kmod] ~> Service<| tag == profile::gpu::services |>
}

class profile::gpu::install::passthrough (
  Array[String] $packages,
  String $nvidia_driver_stream = '550-dkms'
) {
  $os = "rhel${::facts['os']['release']['major']}"
  $arch = $::facts['os']['architecture']

  exec { 'cuda-repo':
    command => "dnf config-manager --add-repo http://developer.download.nvidia.com/compute/cuda/repos/${os}/${arch}/cuda-${os}.repo",
    creates => "/etc/yum.repos.d/cuda-${os}.repo",
    path    => ['/usr/bin'],
  }

  package { 'nvidia-stream':
    ensure      => $nvidia_driver_stream,
    name        => 'nvidia-driver',
    provider    => dnfmodule,
    enable_only => true,
    require     => [
      Exec['cuda-repo'],
    ],
  }

  $mig_profile = lookup("terraform.instances.${facts['networking']['hostname']}.specs.mig", Variant[Undef, Hash[String, Integer]], undef, {})
  class { 'profile::gpu::config::mig':
    mig_profile => $mig_profile,
    require     => Package[$packages],
  }

  package { $packages:
    ensure  => 'installed',
    require => [
      Package['nvidia-stream'],
      Package['kernel-devel'],
      Exec['cuda-repo'],
      Yumrepo['epel'],
    ],
  }

  # Used by slurm-job-exporter to export GPU metrics
  -> package { 'datacenter-gpu-manager': }

  -> augeas { 'nvidia-persistenced.service':
    context => '/files/lib/systemd/system/nvidia-persistenced.service/Service',
    changes => [
      'set DynamicUser/value yes',
      'set StateDirectory/value nvidia-persistenced',
      'set RuntimeDirectory/value nvidia-persistenced',
      'rm ExecStart/arguments',
    ],
  }
}

class profile::gpu::config::mig (
  Variant[Undef, Hash] $mig_profile,
  String $mig_manager_version = '0.5.5',
) {
  $arch = $::facts['os']['architecture']
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

  file_line { 'nvidia-persistenced.service':
    ensure  => present,
    path    => '/etc/nvidia-mig-manager/hooks.sh',
    after   => 'driver_services=\(',
    line    => '        nvidia-persistenced.service',
    require => Package['nvidia-mig-manager'],
  }

  file { '/etc/nvidia-mig-manager/puppet-hooks.yaml':
    require => Package['nvidia-mig-manager'],
    content => @(EOT)
      version: v1
      hooks:
        pre-apply-mode:
        - workdir: "/etc/nvidia-mig-manager"
          command: "/bin/bash"
          args: ["-x", "-c", "source hooks.sh; stop_driver_services"]
        - workdir: "/etc/nvidia-mig-manager"
          command: "/bin/sh"
          args: ["-c", "systemctl -q is-active slurmd && systemctl stop slurmd || true"]
      |EOT
  }

  if $mig_profile and ! $mig_profile.empty {
    $mig_parted_config_name = 'default'
    $mig_parted_config_file = '/etc/nvidia-mig-manager/puppet-config.yaml'
  } else {
    $mig_parted_config_name = 'all-disabled'
    $mig_parted_config_file = '/etc/nvidia-mig-manager/config.yaml'
  }

  exec { 'nvidia-mig-parted apply':
    unless      => 'nvidia-mig-parted assert',
    require     => [
      Package['nvidia-mig-manager'],
      File['/etc/nvidia-mig-manager/puppet-config.yaml'],
      File['/etc/nvidia-mig-manager/puppet-hooks.yaml'],
    ],
    environment => [
      "MIG_PARTED_CONFIG_FILE=${mig_parted_config_file}",
      'MIG_PARTED_HOOKS_FILE=/etc/nvidia-mig-manager/puppet-hooks.yaml',
      "MIG_PARTED_SELECTED_CONFIG=${mig_parted_config_name}",
      'MIG_PARTED_SKIP_RESET=false',
    ],
    path        => ['/usr/bin'],
    notify      => [
      Service['nvidia-persistenced'],
      Service['nvidia-dcgm'],
    ],
  }
  Kmod::Load <| tag == profile::gpu::install |> -> Exec['nvidia-mig-parted apply']
}

class profile::gpu::install::vgpu (
  Enum['rpm', 'bin', 'none'] $installer = 'none',
  String $nvidia_ml_py_version = '11.515.75',
  Array[String] $grid_vgpu_types = [],
) {
  if $installer == 'rpm' {
    include profile::gpu::install::vgpu::rpm
  } elsif $installer == 'bin' {
    # install from binary installer
    include profile::gpu::install::vgpu::bin
  }

  # Used by slurm-job-exporter to export GPU metrics
  # DCGM does not work with GRID VGPU, most of the stats are missing
  ensure_packages(['python3', 'python3-pip'], { ensure => 'present' })
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
  $source_pkg_name = (split($source, '[/]')[-1]).regsubst(/\.rpm/, '', 'G')
  package { 'vgpu-repo':
    ensure   => 'installed',
    provider => 'rpm',
    name     => $source_pkg_name,
    source   => $source,
  }

  package { $packages:
    ensure  => 'installed',
    require => [
      Package['kernel-devel'],
      Yumrepo['epel'],
      Package['vgpu-repo'],
    ],
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
  Optional[String] $gridd_content = undef,
  Optional[String] $gridd_source = undef,
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

  if $gridd_content {
    $gridd_definition = { 'content' => $gridd_content }
  } elsif $gridd_source {
    $gridd_definition = { 'source' => $gridd_source }
  } else {
    $gridd_definition = {}
  }

  file { '/etc/nvidia/gridd.conf':
    ensure => file,
    mode   => '0644',
    owner  => 'root',
    group  => 'root',
    *      => $gridd_definition,
  }
}

class profile::gpu::services {
  if ! profile::is_grid_vgpu() {
    $gpu_services = ['nvidia-persistenced', 'nvidia-dcgm']
  } else {
    $gpu_services = ['nvidia-gridd']
  }
  service { $gpu_services:
    ensure => 'running',
    enable => true,
  }

  exec { 'stop_nvidia_services':
    command     => sprintf('systemctl stop %s', $gpu_services.reverse.join(' ')),
    onlyif      => sprintf('systemctl is-active %s', $gpu_services.reverse.join(' ')),
    refreshonly => true,
    path        => ['/usr/bin'],
  }

  Package<| tag == profile::gpu::install |> -> Service[$gpu_services]
  Exec<| tag == profile::gpu::install::vgpu::bin |> -> Exec[$gpu_services]
}
