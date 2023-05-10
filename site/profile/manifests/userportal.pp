class profile::userportal::server (
  $password
){
  package {['python38', 'python38-devel']: }
  package {['openldap-devel', 'gcc', 'mariadb-devel']: }

  # Using python3.8 with gunicorn
  exec { 'create virtualenv':
    command => '/usr/bin/python3.8 -m venv /var/www/userportal-env',
    creates => '/var/www/userportal-env',
    require => Package['python38'],
  }

  file { '/var/www/userportal/':
    ensure => 'directory',
    owner  => 'apache',
    group  => 'apache',
  }
  -> vcsrepo { '/var/www/userportal/':
    ensure   => present,
    provider => git,
    source   => 'https://github.com/guilbaults/TrailblazingTurtle.git',
    revision => '7940ae14891a60d18afd1d9d009dada044512b0f',
    user     => 'apache',
    notify   => [Service['httpd'], Service['gunicorn-userportal']],
  }
  -> file { '/var/www/userportal/userportal/settings.py':
    show_diff => false,
    content   => epp('profile/userportal/settings.py',
      {
        'password'     => $password,
        'cluster_name' => lookup('profile::slurm::base::cluster_name'),
        'secret_key'   => fqdn_rand_string(32, undef, $password),
        'domain_name'  => lookup('profile::freeipa::base::domain_name'),
        'subdomain'    => lookup('profile::reverse_proxy::userportal_subdomain'),
      }
    ),
    notify    => [Service['httpd'], Service['gunicorn-userportal']],
  }
  -> file { '/var/www/userportal/userportal/common.py':
    source => 'file:/var/www/userportal/example/common.py',
    notify => Service['gunicorn-userportal'],
  }
  -> exec { 'pip install -r':
    command => '/var/www/userportal-env/bin/pip3 install -r /var/www/userportal/requirements.txt',
    require => [Exec['create virtualenv'], Package['python38-devel'], Package['gcc']],
  }

  # Need to use this fork to manage is_staff correctly
  # https://github.com/enervee/django-freeipa-auth/pull/9
  -> exec { 'pip install django-freeipa-auth':
    command => '/var/www/userportal-env/bin/pip3 install git+https://github.com/88Ocelot/django-freeipa-auth.git@d77df67c03a5af5923116afa2f4280b8264b4b5b',
    creates => '/var/www/userportal-env/lib/python3.8/site-packages/freeipa_auth/backends.py',
    require => [Exec['create virtualenv']],
  }

  file { '/var/www/userportal-static':
    ensure => 'directory',
    owner  => 'apache',
    group  => 'apache',
  }

  file { '/etc/httpd/conf.d/userportal.conf':
    content => epp('profile/userportal/userportal.conf.epp'),
    notify  => Service['httpd'],
  }

  file { '/etc/systemd/system/gunicorn-userportal.service':
    mode   => '0755',
    source => 'puppet:///modules/profile/userportal/gunicorn-userportal.service',
    notify => Service['gunicorn-userportal'],
  }

  service { 'gunicorn-userportal':
    ensure  => 'running',
    enable  => true,
    require => Exec['pip install django-freeipa-auth'],
  }

  exec { 'django migrate':
    command => '/var/www/userportal-env/bin/python3 /var/www/userportal/manage.py migrate',
    require => [
      File['/var/www/userportal/userportal/settings.py'],
      File['/var/www/userportal/userportal/common.py'],
      Exec['pip install django-freeipa-auth'],
    ],
  }
  exec { 'django collectstatic':
    command => '/var/www/userportal-env/bin/python3 /var/www/userportal/manage.py collectstatic --noinput',
    require => [
      File['/var/www/userportal/userportal/settings.py'],
      File['/var/www/userportal/userportal/common.py'],
      Exec['pip install django-freeipa-auth'],
    ],
  }

  mysql::db { 'userportal':
    ensure   => present,
    user     => 'userportal',
    password => $password,
    host     => 'localhost',
    grant    => ['ALL'],
    before   => Exec['django migrate'],
  }
}
