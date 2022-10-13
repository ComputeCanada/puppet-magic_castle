class profile::userportal::server (
  $password
){
  $domain_name = lookup('profile::freeipa::base::domain_name')
  package {['python3-virtualenv', 'python3-devel']: }
  package {['openldap-devel', 'gcc', 'mariadb-devel']: }

  exec { 'create virtualenv':
    command => '/usr/bin/virtualenv-3 /var/www/userportal-env',
    unless  => '/usr/bin/test -d /var/www/userportal-env',
    require => Package['python3-virtualenv'],
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
    revision => '3765a813952371947f910921a282fdbeaaf98bd5',
    user     => 'apache',
  }
  -> file { '/var/www/userportal/userportal/settings.py':
    show_diff => false,
    content   => epp('profile/userportal/settings.py',
      {
        'password'     => $password,
        'cluster_name' => lookup('profile::slurm::base::cluster_name'),
        'secret_key'   => fqdn_rand_string(32, undef, $password),
        'domain_name'  => $domain_name,
      }
    ),
    notify => Service['httpd'],
  }
  -> file { '/var/www/userportal/userportal/common.py':
    source => 'file:/var/www/userportal/example/common.py',
    notify => Service['httpd'],
  }
  -> exec { 'pip install -r':
    command => '/var/www/userportal-env/bin/pip3 install -r /var/www/userportal/requirements.txt',
    require => [Exec['create virtualenv'], Package['python3-devel'], Package['gcc']],
  }

  # Need to use this fork to manage is_staff correctly
  # https://github.com/enervee/django-freeipa-auth/pull/9
  -> exec { 'pip install django-freeipa-auth':
    command => '/var/www/userportal-env/bin/pip3 install git+https://github.com/88Ocelot/django-freeipa-auth.git',
    unless => '/var/www/userportal-env/bin/pip3 freeze | /usr/bin/grep django-freeipa-auth',
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

  file { '/etc/systemd/system/gunicorn.service':
    mode    => '0755',
    content => '[Unit]
Description=gunicorn daemon
After=network.target

[Service]
User=apache
Group=apache
RuntimeDirectory=gunicorn
WorkingDirectory=/var/www/userportal/
ExecStart=/var/www/userportal-env/bin/gunicorn --bind 127.0.0.1:8001 --workers 2 --timeout 90 userportal.wsgi
ExecReload=/bin/kill -s HUP $MAINPID
KillMode=mixed
TimeoutStopSec=5
PrivateTmp=true

[Install]
WantedBy=multi-user.target',
    notify => Service['gunicorn'],
  }

  service { 'gunicorn':
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
