class profile::globus::base (String $globus_user = '', String $globus_password = '')
{
  package { 'globus-connect-server-repo':
    ensure   => 'installed',
    name     => 'globus-toolkit-repo-6.0.15-1.noarch',
    provider => 'rpm',
    source   => 'https://downloads.globus.org/toolkit/globus-connect-server/globus-connect-server-repo-latest.noarch.rpm'
  }

  package { 'globus-connect-server':
    ensure  => 'installed',
    require => [Package['yum-plugin-priorities'],
                Package['globus-connect-server-repo']]
  }

  $domain_name = lookup('profile::freeipa::base::domain_name')
  $cluster_name = split($domain_name, '.')[0]
  file { '/etc/globus-connect-server.conf':
    ensure  => 'present',
    content => epp('profile/globus/globus-connect-server.conf', { 'domain_name' => $domain_name,
                                                                  'hostname'    => $cluster_name }),
  }

  if ($globus_user != '') and ($globus_password != '') {

    firewall { '100 Globus connect server - globus.org':
      chain  => 'INPUT'
      dport  => [2811, 7512],
      proto  => 'tcp',
      source => "54.237.254.192/29",
      action => 'accept'
    }

    firewall { '101 Globus connect server - users':
      chain  => 'INPUT'
      dport  => "50000-51000",
      proto  => 'tcp',
      action => 'accept'
    }

    exec { '/usr/bin/globus-connect-server-setup':
      environment => ["GLOBUS_USER=${globus_user}",
                      "GLOBUS_PASSWORD=${globus_password}",
                      "HOME=${::root_home}",
                      "TERM=vt100"],
      refreshonly => true,
      require     => Package['globus-connect-server'],
      subscribe   => File['/etc/globus-connect-server.conf'],
    }
  }
}

class profile::globus::server_v5 {
  package { 'globus-toolkit-repo':
    name     => 'globus-toolkit-repo-6.0.14-1.noarch',
    provider => 'rpm',
    ensure   => 'installed',
    source   => 'http://downloads.globus.org/toolkit/gt6/stable/installers/repo/rpm/globus-toolkit-repo-latest.noarch.rpm'
  }

  yumrepo { 'globus-connect-server-5-stable-el7.repo':
    name    => "Globus-Connect-Server-5-Stable",
    ensure  => present,
    enabled => 1,
    require => Package['globus-toolkit-repo']
  }

  yumrepo { 'globus-toolkit-6-stable-el7.repo':
    name    => "Globus-Toolkit-6-Stable",
    ensure  => present,
    enabled => 1,
    require => Package['globus-toolkit-repo']
  }

  package { 'globus-connect-server51':
    ensure  => 'installed',
    require => [Yumrepo['globus-connect-server-5-stable-el7.repo'],
                Yumrepo['globus-toolkit-6-stable-el7.repo']]
  }
  package { 'globus-connect-server-manager51-selinux':
    ensure  => 'installed',
    require => [Yumrepo['globus-connect-server-5-stable-el7.repo'],
                Yumrepo['globus-toolkit-6-stable-el7.repo']]
  }
}
