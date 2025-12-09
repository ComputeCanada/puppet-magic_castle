class profile::rsyslog::base {
  class { 'rsyslog':
    purge_config_files      => false,
    override_default_config => false,
  }
}

class profile::rsyslog::client {
  include profile::rsyslog::base
  include rsyslog::config

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

  @consul::service { 'rsyslog':
    port => 514,
  }

  file { '/etc/rsyslog.d/98-remotelogs.conf':
    notify  => Service['rsyslog'],
    content => @(EOT)
      $template RemoteLogs,"/var/log/instances/%HOSTNAME%/%PROGRAMNAME%.log"
      if $fromhost-ip != '127.0.0.1' then -?RemoteLogs
      & stop
      |EOT
  }

  logrotate::rule { 'rsyslog_instances':
    path         => '/var/log/instances/*/*.log',
    rotate       => 5,
    ifempty      => false,
    copytruncate => false,
    olddir       => false,
    size         => '5M',
    compress     => true,
    create       => true,
    create_mode  => '0600',
    create_owner => 'root',
    create_group => 'root',
    postrotate   => '/usr/bin/systemctl kill -s HUP rsyslog.service  >/dev/null 2>&1 || true',
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
