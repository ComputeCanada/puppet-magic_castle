class profile::gpu {
  file_line { 'kmod_nvidia_exclude':
    ensure => present,
    path   => '/etc/yum.conf',
    line   => 'exclude=kmod-nvidia* nvidia-x11-drv',
  }

  package { 'kmod-nvidia-390.48':
    ensure  => 'installed',
    require => File_line['kmod_nvidia_exclude']
  }  
}