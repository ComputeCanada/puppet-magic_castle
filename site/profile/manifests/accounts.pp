# @summary Class configuring services to bridge LDAP users, Slurm accounts and users' folders in filesystems
# @param project_regex Regex identifying FreeIPA groups that require a corresponding Slurm account
# @param skel_archives Archives extracted in each FreeIPA user's home when created
class profile::accounts (
  String $project_regex,
  Array[Struct[{ filename => String[1], source => String[1] }]] $skel_archives = [],
) {
  Service <| tag == profile::slurm |> -> Service['mkhome']
  Service <| tag == profile::slurm |> -> Service['mkproject']
  Service <| tag == profile::freeipa |> -> Service['mkhome']
  Service <| tag == profile::freeipa |> -> Service['mkproject']
  Mount <| |> -> Service['mkhome']
  Mount <| |> -> Service['mkproject']

  $nfs_devices = lookup('profile::nfs::server::devices', undef, undef, {})
  $with_home = 'home' in $nfs_devices
  $with_project = 'project' in $nfs_devices
  $with_scratch = 'scratch' in $nfs_devices

  package { 'rsync':
    ensure => 'installed',
  }

  file { 'account_functions.sh':
    path   => '/sbin/account_functions.sh',
    source => 'puppet:///modules/profile/accounts/account_functions.sh',
  }

  file { '/sbin/mkhome.sh':
    content => epp('profile/accounts/mkhome.sh',
      {
        with_home    => $with_home,
        with_scratch => $with_scratch,
      }
    ),
    mode    => '0755',
    owner   => 'root',
  }

  file { 'mkhome.service':
    path   => '/lib/systemd/system/mkhome.service',
    source => 'puppet:///modules/profile/accounts/mkhome.service',
  }

  file { '/etc/skel.ipa':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { '/etc/skel.ipa/.bash_logout':
    source  => 'file:///etc/skel/.bash_logout',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => File['/etc/skel.ipa'],
  }

  file { '/etc/skel.ipa/.bash_profile':
    source  => 'file:///etc/skel/.bash_profile',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => File['/etc/skel.ipa'],
  }

  file { '/etc/skel.ipa/.bashrc':
    source  => 'file:///etc/skel/.bashrc',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => File['/etc/skel.ipa'],
  }

  ensure_resource('file', '/opt/puppetlabs/puppet/cache/puppet-archive', { 'ensure' => 'directory' })
  $skel_archives.each |$index, Hash $archive| {
    $filename = $archive['filename']
    archive { "skel_${index}":
      path         => "/opt/puppetlabs/puppet/cache/puppet-archive/${filename}",
      extract      => true,
      extract_path => '/etc/skel.ipa',
      source       => $archive['source'],
      require      => File['/etc/skel.ipa'],
      notify       => Exec['chown -R root:root /etc/skel.ipa'],
    }
  }

  exec { 'chown -R root:root /etc/skel.ipa':
    refreshonly => true,
    path        => ['/bin/', '/usr/bin'],
  }

  $mkhome_running = $with_home or $with_scratch
  service { 'mkhome':
    ensure    => $mkhome_running,
    enable    => $mkhome_running,
    subscribe => [
      File['/sbin/mkhome.sh'],
      File['/sbin/account_functions.sh'],
      File['mkhome.service'],
    ],
  }

  file { 'mkproject.service':
    path   => '/lib/systemd/system/mkproject.service',
    source => 'puppet:///modules/profile/accounts/mkproject.service',
  }

  file { '/sbin/mkproject.sh':
    content => epp('profile/accounts/mkproject.sh',
      {
        project_regex => $project_regex,
        with_folder   => $with_project,
      }
    ),
    mode    => '0755',
    owner   => 'root',
  }

  # mkproject is always running even if /project does not exist
  # because it also handles the creation of Slurm accounts
  service { 'mkproject':
    ensure    => running,
    enable    => true,
    subscribe => [
      File['/sbin/mkproject.sh'],
      File['/sbin/account_functions.sh'],
      File['mkproject.service'],
    ],
  }
}
