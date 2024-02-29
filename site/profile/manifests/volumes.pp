# lookup_options:
#   profile::volumes::devices:
#     merge: 'deep'

## common.yaml
# profile::volumes::devices: %{alias('terraform.self.volumes')}

## Provided by the user
# profile::volumes::devices:
#   nfs:
#     home:
#       mode: '0600'
#       owner: 'root'
#       group: 'root'

class profile::volumes (
  Hash[String, Hash[String, Hash]] $devices,
) {
  if $devices =~ Hash[String, Hash[String, Hash]] {
    package { 'lvm2':
      ensure => installed,
    }
    $devices.each | String $volume_tag, $device_map | {
      ensure_resource('file', "/mnt/${volume_tag}", { 'ensure' => 'directory' })
      $device_map.each | String $key, $values | {
        profile::volumes::volume { "${volume_tag}-${key}":
          volume_name   => $key,
          volume_tag    => $volume_tag,
          glob          => $values['glob'],
          bind_mount    => pick($values['bind_mount'], true),
          bind_target   => pick($values['bind_target'], "/${key}"),
          owner         => pick($values['owner'], 'root'),
          group         => pick($values['group'], 'root'),
          mode          => pick($values['mode'], '0644'),
          seltype       => pick($values['seltype'], 'home_root_t'),
          enable_resize => pick($values['autoresize'], false),
          require       => File["/mnt/${volume_tag}"],
        }
      }
    }
  }
}

define profile::volumes::volume (
  String $volume_name,
  String $volume_tag,
  String $glob,
  String $owner,
  String $mode,
  String $group,
  String $bind_target,
  Boolean $bind_mount,
  String $seltype,
  Boolean $enable_resize,
) {
  $regex = Regexp(regsubst($glob, /[?*]/, { '?' => '.', '*' => '.*' }))

  file { "/mnt/${volume_tag}/${volume_name}":
    ensure  => 'directory',
    owner   => $owner,
    group   => $group,
    mode    => $mode,
    seltype => $seltype,
  }

  $device = (values($::facts['/dev/disk'].filter |$k, $v| { $k =~ $regex }).unique)[0]

  exec { "vgchange-${name}_vg":
    command => "vgchange -ay ${name}_vg",
    onlyif  => ["test ! -d /dev/${name}_vg", "vgscan -t | grep -q '${name}_vg'"],
    require => [Package['lvm2']],
    path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
  }

  physical_volume { $device:
    ensure => present,
  }

  volume_group { "${name}_vg":
    ensure           => present,
    physical_volumes => $device,
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

  if $enable_resize {
    $logical_volume_size_cmd = "pvs --noheadings -o pv_size ${device} | sed -nr 's/^.*[ <]([0-9]+)\\..*g$/\\1/p'"
    $physical_volume_size_cmd = "pvs --noheadings -o dev_size ${device} | sed -nr 's/^ *([0-9]+)\\..*g/\\1/p'"
    exec { "pvresize ${device}":
      onlyif  => "test `${logical_volume_size_cmd}` -lt `${physical_volume_size_cmd}`",
      path    => ['/usr/bin', '/bin', '/usr/sbin'],
      require => Lvm::Logical_volume[$name],
    }

    $pv_freespace_cmd = "pvs --noheading -o pv_free ${device} | sed -nr 's/^ *([0-9]*)\\..*g/\\1/p'"
    exec { "lvextend -l '+100%FREE' -r /dev/${name}_vg/${name}":
      onlyif  => "test `${pv_freespace_cmd}` -gt 0",
      path    => ['/usr/bin', '/bin', '/usr/sbin'],
      require => Exec["pvresize ${device}"],
    }
  }

  selinux::fcontext::equivalence { "/mnt/${volume_tag}/${volume_name}":
    ensure  => 'present',
    target  => '/home',
    require => Mount["/mnt/${volume_tag}/${volume_name}"],
    notify  => Selinux::Exec_restorecon["/mnt/${volume_tag}/${volume_name}"],
  }

  selinux::exec_restorecon { "/mnt/${volume_tag}/${volume_name}": }

  if $bind_mount {
    ensure_resource('file', $bind_target, { 'ensure' => 'directory', 'seltype' => $seltype })
    mount { $bind_target:
      ensure  => mounted,
      device  => "/mnt/${volume_tag}/${volume_name}",
      fstype  => none,
      options => 'rw,bind',
      require => File[$bind_target],
    }
  }
}
