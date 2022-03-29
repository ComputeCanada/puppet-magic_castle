class profile::accounts (
  String $project_regex,
  Array[Struct[{filename => String[1], source => String[1]}]] $skel_archives = [],
) {
  require profile::freeipa::server
  require profile::freeipa::mokey
  require profile::nfs::server
  require profile::slurm::accounting

  $nfs_devices = lookup('profile::nfs::server::devices', undef, undef, {})
  $with_home = 'home' in $nfs_devices
  $with_project = 'project' in $nfs_devices
  $with_scratch = 'scratch' in $nfs_devices

  file { '/sbin/mkhome.sh':
    ensure  => 'present',
    content => epp('profile/accounts/mkhome.sh', {
      with_home    => $with_home,
      with_scratch => $with_scratch,
    }),
    mode    => '0755',
    owner   => 'root',
  }

  file { 'mkhome.service':
    ensure => 'present',
    path   => '/lib/systemd/system/mkhome.service',
    source => 'puppet:///modules/profile/accounts/mkhome.service'
  }

  file { '/etc/skel.ipa':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { '/etc/skel.ipa/.bash_logout':
    ensure  => present,
    source  => 'file:///etc/skel/.bash_logout',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => File['/etc/skel.ipa']
  }

  file { '/etc/skel.ipa/.bash_profile':
    ensure  => present,
    source  => 'file:///etc/skel/.bash_profile',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => File['/etc/skel.ipa']
  }

  file { '/etc/skel.ipa/.bashrc':
    ensure  => present,
    source  => 'file:///etc/skel/.bashrc',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => File['/etc/skel.ipa']
  }

  $skel_archives.each |$index, Hash $archive| {
    $filename = $archive['filename']
    archive { "skel_${index}":
      path         => "/tmp/${filename}",
      cleanup      => true,
      extract      => true,
      extract_path => '/etc/skel.ipa',
      source       => $archive['source'],
      require      => File['/etc/skel.ipa'],
      notify       => Exec['chown -R root:root /etc/skel.ipa'],
    }
  }

  exec { 'chown -R root:root /etc/skel.ipa':
    refreshonly => true,
    require     => File['/etc/skel.ipa']
  }

  if $with_home or $with_scratch {
    service { 'mkhome':
      ensure    => running,
      enable    => true,
      subscribe => [
        File['/sbin/mkhome.sh'],
        File['mkhome.service'],
      ]
    }
  }

  file { 'mkproject.service':
    ensure => 'present',
    path   => '/lib/systemd/system/mkproject.service',
    source => 'puppet:///modules/profile/accounts/mkproject.service'
  }

  file { '/sbin/mkproject.sh':
    ensure  => 'present',
    content => epp('profile/accounts/mkproject.sh', {
      project_regex => $project_regex,
      with_folder   => $with_project,
    }),
    mode    => '0755',
    owner   => 'root',
  }

  service { 'mkproject':
    ensure    => running,
    enable    => true,
    subscribe => [
      File['/sbin/mkproject.sh'],
      File['mkproject.service'],
    ]
  }
}

