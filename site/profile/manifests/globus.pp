class profile::globus::base (String $globus_user = '', String $globus_password = '')
{
  package { 'globus-connect-server-repo':
    ensure   => 'latest',
    name     => 'globus-toolkit-repo',
    provider => 'rpm',
    source   => 'https://downloads.globus.org/toolkit/globus-connect-server/globus-connect-server-repo-latest.noarch.rpm'
  }

  $domain_name = lookup('profile::freeipa::base::domain_name')

  if $domain_name in $::facts['letsencrypt'] {
    $privkey_exists = $::facts['letsencrypt'][$domain_name]['privkey']
    $fullchain_exists = $::facts['letsencrypt'][$domain_name]['fullchain']
  } else {
    $privkey_exists = false
    $fullchain_exists = false
  }

  if $globus_user != '' and $globus_password != '' {
    if dig($::facts, 'os', 'release', 'major') == '7' {
      $required_pkg = [
        Package['yum-plugin-priorities'],
        Package['globus-connect-server-repo']
      ]
    } else {
      $required_pkg = [
        Package['globus-connect-server-repo']
      ]
    }
    package { 'globus-connect-server':
      ensure  => 'installed',
      require => $required_pkg,
    }

    if $privkey_exists and $fullchain_exists {
      apache::vhost { "dtn.${domain_name}":
        port                        => '443',
        docroot                     => false,
        wsgi_daemon_process         => 'myproxyoauth',
        wsgi_daemon_process_options => {
          user    => 'myproxyoauth',
          group   => 'myproxyoauth',
          threads => '1',
        },
        wsgi_process_group          => 'myproxyoauth',
        wsgi_script_aliases         => { '/oauth' => '/usr/share/myproxy-oauth/wsgi.py' },
        directories                 => [
          {
            path     => '/usr/share/myproxy-oauth/myproxyoauth',
            requires => 'all granted',
            # ssl_require_ssl => true,
          },
          {
            path     => '/usr/share/myproxy-oauth/',
            requires => 'all granted',
            # ssl_require_ssl => true,
          },
          {
            path     => '/usr/share/myproxy-oauth/myproxyoauth/static',
            requires => 'all granted',
            options  => ['Indexes'],
          },
          {
            path     => '/usr/share/myproxy-oauth/myproxyoauth/templates',
            requires => 'all granted',
            options  => ['Indexes'],
          },
        ],
        aliases                     => [
          {
            alias => '/oauth/templates/',
            path  => '/usr/share/myproxy-oauth/myproxyoauth/templates/',
          },
          {
            alias => '/oauth/static/',
            path  => '/usr/share/myproxy-oauth/myproxyoauth/static/',
          },
        ],
        ssl                         => true,
        ssl_cert                    => "/etc/letsencrypt/live/${domain_name}/fullchain.pem",
        ssl_key                     => "/etc/letsencrypt/live/${domain_name}/privkey.pem",
      }
      file { '/etc/globus-connect-server.conf':
        ensure  => 'present',
        content => epp('profile/globus/globus-connect-server.conf', { 'hostname' => "dtn.${domain_name}" }),
      }
    }

    firewall { '100 Globus connect server - globus.org':
      chain  => 'INPUT',
      dport  => [2811],
      proto  => 'tcp',
      source => '54.237.254.192/29',
      action => 'accept'
    }

    firewall { '101 Globus connect server - myproxy':
      chain  => 'INPUT',
      dport  => [7512],
      proto  => 'tcp',
      action => 'accept'
    }

    firewall { '102 Globus connect server - users':
      chain  => 'INPUT',
      dport  => '50000-51000',
      proto  => 'tcp',
      action => 'accept'
    }

    exec { '/usr/bin/globus-connect-server-setup':
      environment => ["GLOBUS_USER=${globus_user}",
                      "GLOBUS_PASSWORD=${globus_password}",
                      "HOME=${::root_home}",
                      'TERM=vt100'],
      refreshonly => true,
      require     => Package['globus-connect-server'],
      subscribe   => File['/etc/globus-connect-server.conf'],
    }

    service { 'myproxy-server':
      ensure  => running,
      enable  => true,
      require => Exec['/usr/bin/globus-connect-server-setup']
    }

    service { 'globus-gridftp-server':
      ensure  => running,
      enable  => true,
      require => Exec['/usr/bin/globus-connect-server-setup']
    }
  }
}
