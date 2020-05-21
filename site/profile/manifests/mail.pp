class profile::mail::server {
  ensure_packages(['postfix'], { ensure => 'present'})

  service { 'postfix':
    ensure  => running,
    enable  => true,
    require => Package['postfix'],
  }
}
