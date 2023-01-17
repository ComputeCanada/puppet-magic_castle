class profile::userportal::server (String $password) {
  package { ['python38', 'python38-devel']: }
  package { ['openldap-devel', 'gcc', 'mariadb-devel']: }

  # Using python3.8 with gunicorn
  exec { 'userportal_venv':
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
    source          => 'https://github.com/guilbaults/TrailblazingTurtle/archive/refs/tags/v1.0.2.tar.gz',
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
        'password'       => $password,
        'slurm_password' => lookup('profile::slurm::accounting::password'),
        'cluster_name'   => lookup('profile::slurm::base::cluster_name'),
        'secret_key'     => fqdn_rand_string(32, undef, $password),
        'domain_name'    => lookup('profile::freeipa::base::domain_name'),
        'subdomain'      => lookup('profile::reverse_proxy::userportal_subdomain'),
      }
    ),
    notify    => [Service['httpd'], Service['gunicorn-userportal']],
  }
  -> file { '/var/www/userportal/userportal/local.py':
    source => 'file:/var/www/userportal/example/local.py',
    notify => Service['gunicorn-userportal'],
  }

  exec { 'userportal_pip':
    command     => '/var/www/userportal-env/bin/pip3 install -r /var/www/userportal/requirements.txt',
    refreshonly => true,
    subscribe   => Archive['userportal'],
    require     => [
      Exec['userportal_venv'],
      Package['python38-devel'],
      Package['gcc']
    ],
  }

  # Need to use this fork to manage is_staff correctly
  # https://github.com/enervee/django-freeipa-auth/pull/9
  -> exec { 'pip install django-freeipa-auth':
    command => '/var/www/userportal-env/bin/pip3 install git+https://github.com/88Ocelot/django-freeipa-auth.git@d77df67c03a5af5923116afa2f4280b8264b4b5b',
    creates => '/var/www/userportal-env/lib/python3.8/site-packages/freeipa_auth/backends.py',
    require => [Exec['userportal_venv']],
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
    mode   => '0644',
    source => 'puppet:///modules/profile/userportal/gunicorn-userportal.service',
    notify => Service['gunicorn-userportal'],
  }

  service { 'gunicorn-userportal':
    ensure  => 'running',
    enable  => true,
    require => Exec['pip install django-freeipa-auth'],
  }

  exec { 'userportal_migrate':
    command     => '/var/www/userportal-env/bin/python3 /var/www/userportal/manage.py migrate',
    refreshonly => true,
    subscribe   => Mysql::Db['userportal'],
    require     => [
      File['/var/www/userportal/userportal/settings/99-local.py'],
      File['/var/www/userportal/userportal/local.py'],
      Exec['pip install django-freeipa-auth'],
    ],
  }
  exec { 'userportal_collectstatic':
    command => '/var/www/userportal-env/bin/python3 /var/www/userportal/manage.py collectstatic --noinput',
    require => [
      File['/var/www/userportal/userportal/settings/99-local.py'],
      File['/var/www/userportal/userportal/local.py'],
      Exec['pip install django-freeipa-auth'],
    ],
    creates => [
      '/var/www/userportal-static/admin',
      '/var/www/userportal-static/custom.js',
      '/var/www/userportal-static/dashboard.css',
    ],
  }

  $domain = lookup('profile::freeipa::base::domain_name')
  exec { 'userportal_apiuser':
    command     => "/var/www/userportal-env/bin/python /var/www/userportal/manage.py createsuperuser --noinput --username root --email root@${domain}",
    refreshonly => true,
    subscribe   => Exec['userportal_migrate'],
    returns     => [0, 1], # ignore error if user already exists
  }

  file { '/etc/slurm/slurm_jobscripts.ini':
    ensure  => 'file',
    owner   => 'slurm',
    group   => 'slurm',
    mode    => '0600',
    replace => false,
    content => @(EOT),
[slurm]
spool = /var/spool/slurm

[api]
host = http://localhost:8001
script_length = 100000
|EOT
  }

  exec { 'userportal_api_token':
    command     => 'manage.py drf_create_token root | awk \'{print "token = " $3}\' >> /etc/slurm/slurm_jobscripts.ini',
    refreshonly => true,
    require     => '/etc/slurm/slurm_jobscripts.ini',
    subscribe   => [
      File['/etc/slurm/slurm_jobscripts.ini'],
      Exec['userportal_apiuser'],
    ],
    notify      => Service['slurm_jobscripts'],
    path        => [
      '/var/www/userportal',
      '/var/www/userportal-env/bin',
      '/usr/bin',
    ]
  }

  file { '/etc/systemd/system/slurm_jobscripts.service':
    mode   => '0644',
    source => 'puppet:///modules/profile/userportal/slurm_jobscripts.service',
    notify => Service['slurm_jobscripts'],
  }

  service { 'slurm_jobscripts':
    ensure  => 'running',
    enable  => true,
    require => Exec['userportal_api_token'],
  }

  mysql::db { 'userportal':
    ensure   => present,
    user     => 'userportal',
    password => $password,
    host     => 'localhost',
    grant    => ['ALL'],
  }
}
