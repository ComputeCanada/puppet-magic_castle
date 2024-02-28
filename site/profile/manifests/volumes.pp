class profile::volumes (
  Hash[String, Hash[String, Array[String]]] $devices,
) {
  if $devices =~ Hash[String, Hash[String, Array[String]]] {
    package { 'lvm2':
      ensure => installed,
    }
    $devices.each | String $volume_tag, $device_map | {
      ensure_resource('file', "/mnt/${volume_tag}", { 'ensure' => 'directory' })
      $device_map.each | String $key, $glob | {
        profile::volumes::volume { "${volume_tag}-${key}":
          volume_name     => $key,
          volume_tag      => $volume_tag,
          glob            => $glob,
          root_bind_mount => true,
          require         => File["/mnt/${volume_tag}"],
        }
      }
    }
  }
}

define profile::volumes::volume (
  String $volume_name,
  String $volume_tag,
  Array[String] $glob,
  Boolean $root_bind_mount = false,
  String $seltype = 'home_root_t',
) {
  $regexes = regsubst($glob, /[?*]/, { '?' => '.', '*' => '.*' })

  ensure_resource('file', "/mnt/${volume_tag}/${volume_name}", { 'ensure' => 'directory', 'seltype' => $seltype })

  $pool = $::facts['/dev/disk'].filter |$k, $v| {
    $regexes.any|$regex| {
      $k =~ Regexp($regex)
    }
  }.map |$k, $v| {
    $v
  }.unique

  exec { "vgchange-${name}_vg":
    command => "vgchange -ay ${name}_vg",
    onlyif  => ["test ! -d /dev/${name}_vg", "vgscan -t | grep -q '${name}_vg'"],
    require => [Package['lvm2']],
    path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
  }

  physical_volume { $pool:
    ensure => present,
  }

  volume_group { "${name}_vg":
    ensure           => present,
    physical_volumes => $pool,
    createonly       => true,
    followsymlinks   => true,
  }

  lvm::logical_volume { $name:
    ensure            => present,
    volume_group      => "${name}_vg",
    fs_type           => 'xfs',
    mountpath         => "/mnt/${volume_tag}/${volume_name}",
    mountpath_require => true,
  }

  selinux::fcontext::equivalence { "/mnt/${volume_tag}/${volume_name}":
    ensure  => 'present',
    target  => '/home',
    require => Mount["/mnt/${volume_tag}/${volume_name}"],
    notify  => Selinux::Exec_restorecon["/mnt/${volume_tag}/${volume_name}"],
  }

  selinux::exec_restorecon { "/mnt/${volume_tag}/${volume_name}": }

  if $root_bind_mount {
    ensure_resource('file', "/${volume_name}", { 'ensure' => 'directory', 'seltype' => $seltype })
    mount { "/${volume_name}":
      ensure  => mounted,
      device  => "/mnt/${volume_tag}/${volume_name}",
      fstype  => none,
      options => 'rw,bind',
      require => File["/${volume_name}"],
    }
  }
}
