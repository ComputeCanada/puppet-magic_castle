class profile::globus {
  package { 'wget':
    ensure => installed,
  }
  include globus
  Package['wget'] -> Class['globus']
}
