class profile::rsyslog::base {
  package { 'rsyslog':
    ensure => 'installed'
  }
  service { 'rsyslog':
    ensure => running,
    enable => true
  }
}

class profile::rsyslog::client {
  include profile::rsyslog::base

  file { '/etc/rsyslog.d/remote_host.conf.ctmpl':
    ensure  => present,
    content => @(END)
{{ range service "rsyslog" -}}
*.* @@{{.Address}}:{{.Port}}
{{ end -}}
END
  }

  consul_template::watch { 'slurm.remote_host.conf.ctmpl':
    require     => File['/etc/rsyslog.d/remote_host.conf.ctmpl'],
    config_hash => {
      perms       => '0644',
      source      => '/etc/rsyslog.d/remote_host.conf.ctmpl',
      destination => '/etc/rsyslog.d/remote_host.conf',
      command     => 'systemctl restart rsyslog || true',
    }
  }
}

class profile::rsyslog::server {
  include profile::rsyslog::base

  consul::service { 'rsyslog':
    port    => 514,
    require => Tcp_conn_validator['consul'],
    token   => lookup('profile::consul::acl_api_token'),
  }

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
