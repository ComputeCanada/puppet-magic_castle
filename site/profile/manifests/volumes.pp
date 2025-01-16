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
#       quota: '5g'

class profile::volumes (
  Hash[String, Hash[String, Hash]] $devices,
) {
  package { 'lvm2':
    ensure => installed,
  }
  $devices.each | String $volume_tag, $device_map | {
    ensure_resource('file', "/mnt/${volume_tag}", { 'ensure' => 'directory' })
    $device_map.each | String $key, $values | {
      profile::volumes::volume { "${volume_tag}-${key}":
        volume_name => $key,
        volume_tag  => $volume_tag,
        *           => $values,
      }
    }
  }
}

define profile::volumes::volume (
  String $volume_name,
  String $volume_tag,
  String $glob,
  Integer $size,
  String $owner = 'root',
  String $mode = '0755',
  String $group = 'root',
  Boolean $bind_mount = true,
  String $seltype = 'home_root_t',
  Boolean $enable_resize = false,
  Enum['xfs', 'ext3', 'ext4'] $filesystem = 'xfs',
  Optional[String[1]] $quota = undef,
  Optional[String[1]] $type = undef,
  Optional[String[1]] $mkfs_options = undef,
  Optional[String[1]] $bind_target = undef,
) {
  $regex = Regexp(regsubst($glob, /[?*]/, { '?' => '.', '*' => '.*' }))
  $bind_target_ = pick($bind_target, "/${volume_name}")

  file { "/mnt/${volume_tag}/${volume_name}":
    ensure  => 'directory',
    owner   => $owner,
    group   => $group,
    mode    => $mode,
    seltype => $seltype,
  }

  $device = (values($::facts['/dev/disk'].filter |$k, $v| { $k =~ $regex }).unique)[0]
  $dev_mapper_id = "/dev/mapper/${volume_tag}--${volume_name}_vg-${volume_tag}--${volume_name}"

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

  if $filesystem == 'xfs' {
    $options = 'defaults,usrquota'
  } else {
    $options = 'defaults'
  }

  lvm::logical_volume { $name:
    ensure            => present,
    volume_group      => "${name}_vg",
    fs_type           => $filesystem,
    mkfs_options      => $mkfs_options,
    mountpath         => "/mnt/${volume_tag}/${volume_name}",
    mountpath_require => true,
    options           => $options,
  }

  exec { "chown ${owner}:${group} /mnt/${volume_tag}/${volume_name}":
    onlyif      => "test \"$(stat -c%U:%G /mnt/${volume_tag}/${volume_name})\" != \"${owner}:${group}\"",
    refreshonly => true,
    subscribe   => Lvm::Logical_volume[$name],
    path        => ['/bin'],
  }

  exec { "chmod ${mode} /mnt/${volume_tag}/${volume_name}":
    onlyif      => "test \"$(stat -c0%a /mnt/${volume_tag}/${volume_name})\" != \"${mode}\"",
    refreshonly => true,
    subscribe   => Lvm::Logical_volume[$name],
    path        => ['/bin'],
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
    ensure_resource('file', $bind_target_, { 'ensure' => 'directory', 'seltype' => $seltype })
    mount { $bind_target_:
      ensure  => mounted,
      device  => "/mnt/${volume_tag}/${volume_name}",
      fstype  => none,
      options => 'rw,bind',
      require => [
        File[$bind_target_],
        Lvm::Logical_volume[$name],
      ],
    }
  } elsif (
    $facts['mountpoints'][$bind_target_] != undef and
    $facts['mountpoints'][$bind_target_]['device'] == $dev_mapper_id
  ) {
    mount { $bind_target_:
      ensure  => absent,
    }
  }

  if $quota and $filesystem == 'xfs' {
    ensure_resource('file', '/etc/xfs_quota', { 'ensure' => 'directory' })
    # Save the xfs quota setting to avoid applying at every iteration
    file { "/etc/xfs_quota/${volume_tag}-${volume_name}":
      ensure  => 'file',
      content => "#FILE TRACKED BY PUPPET DO NOT EDIT MANUALLY\n${quota}",
      require => File['/etc/xfs_quota'],
    }

    exec { "apply-quota-${name}":
      command     => "xfs_quota -x -c 'limit bsoft=${quota} bhard=${quota} -d' /mnt/${volume_tag}/${volume_name}",
      require     => Mount["/mnt/${volume_tag}/${volume_name}"],
      path        => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
      refreshonly => true,
      subscribe   => [File["/etc/xfs_quota/${volume_tag}-${volume_name}"]],
    }
  }
}
