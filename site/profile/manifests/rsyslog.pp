class profile::rsyslog::base {
}

class profile::rsyslog::client {
  include profile::rsyslog::base

  $remote_host_conf = @(EOT)
    {{ with $local := node -}}
    {{ range service "rsyslog" -}}
    {{ if ne $local.Node.Address .Address -}}
    *.* @@{{.Address}}:{{.Port}}
    {{ end -}}
    {{ end -}}
    {{ end -}}
    | EOT
  file { '/etc/rsyslog.d/remote_host.conf.ctmpl':
    content => $remote_host_conf,
    notify  => Service['consul-template'],
  }

  consul_template::watch { 'remote_host.conf.ctmpl':
    require     => File['/etc/rsyslog.d/remote_host.conf.ctmpl'],
    config_hash => {
      perms       => '0644',
      source      => '/etc/rsyslog.d/remote_host.conf.ctmpl',
      destination => '/etc/rsyslog.d/99-remote_host.conf',
      command     => 'systemctl restart rsyslog || true',
    },
  }
}

class profile::rsyslog::server {
  include profile::rsyslog::base

  consul::service { 'rsyslog':
    port    => 514,
    require => Tcp_conn_validator['consul'],
    token   => lookup('profile::consul::acl_api_token'),
  }

  file { '/etc/rsyslog.d/98-remotelogs.conf':
    notify  => Service['rsyslog'],
    content => @(EOT)
      $template RemoteLogs,"/var/log/%HOSTNAME%/%PROGRAMNAME%.log"
      if $fromhost-ip != '127.0.0.1' then -?RemoteLogs
      & stop
      |EOT
  }

  file_line { 'rsyslog_modload_imtcp':
    ensure => present,
    path   => '/etc/rsyslog.conf',
    match  => '^#$ModLoad imtcp',
    line   => '$ModLoad imtcp',
    notify => Service['rsyslog'],
  }

  file_line { 'rsyslog_InputTCPServerRun':
    ensure => present,
    path   => '/etc/rsyslog.conf',
    match  => '^#$InputTCPServerRun 514',
    line   => '$InputTCPServerRun 514',
    notify => Service['rsyslog'],
  }
}
