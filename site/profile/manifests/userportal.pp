class profile::userportal::server (
  $password
){
  package {['python3-virtualenv']: }
  package {['openldap-devel', 'gcc', 'mariadb-devel']: }

  exec { 'create virtualenv':
    command => '/usr/bin/virtualenv-3 /var/www/userportal-env',
    unless  => '/usr/bin/test -d /var/www/userportal-env',
    require => Package['python3-virtualenv'],
  }

  # TODO git clone
  file { '/var/www/userportal/':
    ensure => 'directory',
  }
  -> file { '/var/www/userportal/userportal/settings.py':
    show_diff => false,
    content   => epp('profile/userportal/settings.py',
      {
        'password'     => $password,
        'cluster_name' => lookup('profile::slurm::base::cluster_name'),
        'secret_key'   => fqdn_rand_string(32, undef, $password),
        'fqdn'         => $fqdn,
      }
    ),
  }

  exec {'/var/www/userportal-env/bin/pip3 install -r /var/www/userportal/requirements.txt':
    require => [Exec['create virtualenv'], File['/var/www/userportal/']],
  }

  # Need to use this fork to manage is_staff correctly
  # https://github.com/enervee/django-freeipa-auth/pull/9
  exec {'/var/www/userportal-env/bin/pip3 install git+https://github.com/88Ocelot/django-freeipa-auth.git':
    require => [Exec['create virtualenv'], File['/var/www/userportal/']],
  }

  # TODO
  # python manage.py migrate
  # python manage.py collectstatic

  mysql::db { 'userportal':
    ensure   => present,
    user     => 'userportal',
    password => $password,
    host     => 'localhost',
    grant    => ['ALL'],
  }
}
