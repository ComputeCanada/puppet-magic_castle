class profile::cvmfs::client (String $squid_server = "mgmt01") {
  package { 'cvmfs-repo':
    name     => 'cvmfs-release-2-6.noarch',
    provider => 'rpm',
    ensure   => 'installed',
    source   => 'https://ecsft.cern.ch/dist/cvmfs/cvmfs-release/cvmfs-release-latest.noarch.rpm'
  }
  package { 'cc-cvmfs-repo':
    name     => 'computecanada-release-1.0-1.noarch',
    provider => 'rpm',
    ensure   => 'installed',
    source   => 'https://package.computecanada.ca/yum/cc-cvmfs-public/Packages/computecanada-release-1.0-1.noarch.rpm'
  }
  package { ['cvmfs', 'cvmfs-config-computecanada', 'cvmfs-config-default', 'cvmfs-auto-setup']:
    ensure => 'installed',
    require => [Package['cvmfs-repo'], Package['cc-cvmfs-repo']]
  }
  file { '/etc/cvmfs/default.local':
    ensure  => 'present',
    content => file('cvmfs/default.local'),
    require => Package['cvmfs']
  }
  file { '/etc/profile.d/z-00-computecanada.sh':
    ensure  => 'present',
    content => file('cvmfs/z-00-computecanada.sh'),
    require => File['/etc/cvmfs/default.local']
  }
  service { 'autofs':
    ensure  => running,
    enable  => true,
    require => File['/etc/cvmfs/default.local']
  }
}
