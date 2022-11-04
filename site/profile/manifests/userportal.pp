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
  -> archive { 'userportal':
    ensure          => present,
    source          => 'https://github.com/guilbaults/TrailblazingTurtle/archive/refs/tags/v1.0.1.tar.gz',
    path            => '/tmp/userportal.tar.gz',
    extract         => true,
    extract_path    => '/var/www/userportal/',
    extract_command => 'tar xfz %s --strip-components=1',
    cleanup         => true,
    user            => 'apache',
    notify          => [Service['httpd'], Service['gunicorn-userportal']],
  }
  -> file { '/var/www/userportal/userportal/settings/99-local.py':
    show_diff => false,
    content   => epp('profile/userportal/99-local.py',
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
  -> file { '/var/www/userportal/userportal/local.py':
    source => 'file:/var/www/userportal/example/local.py',
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
      File['/var/www/userportal/userportal/settings/99-local.py'],
      File['/var/www/userportal/userportal/local.py'],
      Exec['pip install django-freeipa-auth'],
    ],
  }
  exec { 'django collectstatic':
    command => '/var/www/userportal-env/bin/python3 /var/www/userportal/manage.py collectstatic --noinput',
    require => [
      File['/var/www/userportal/userportal/settings/99-local.py'],
      File['/var/www/userportal/userportal/local.py'],
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
