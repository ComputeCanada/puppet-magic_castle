class profile::rsyslog::base {
  package { 'rsyslog':
    ensure => 'installed'
  }
  service { 'rsyslog':
    ensure => running,
    enable => true
  }
}

class profile::rsyslog::client (String $server_ip) {
  include profile::rsyslog::base
  file_line { 'remote_host':
    ensure => present,
    path   => '/etc/rsyslog.conf',
    match  => '^#\*.\* @@remote-host:514',
    line   => "*.* @@${server_ip}:514",
    notify => Service['rsyslog']
  }
}

class profile::rsyslog::server {
  include profile::rsyslog::base
  file_line { 'rsyslog_modload_imtcp':
    ensure => present,
    path   => '/etc/rsyslog.conf',
    match  => '^#$ModLoad imtcp',
    line   => '$ModLoad imtcp',
    notify => Service['rsyslog']
  }
  file_line { 'rsyslog_InputTCPServerRun':
    ensure => present,
    path   => '/etc/rsyslog.conf',
    match  => '^#$InputTCPServerRun 514',
    line   => '$InputTCPServerRun 514',
    notify => Service['rsyslog']
  }
}
