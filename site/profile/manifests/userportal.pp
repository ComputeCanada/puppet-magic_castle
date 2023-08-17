class profile::userportal::server (
  String $root_api_token,
  String $password,
  String $prometheus_ip,
  Integer $prometheus_port,
  String $db_ip,
  Integer $db_port,
) {
  $instances = lookup('terraform.instances')
  $logins = $instances.filter |$keys, $values| { 'login' in $values['tags'] }

  include profile::userportal::install_tarball

  $domain_name = lookup('profile::freeipa::base::domain_name')
  $int_domain_name = "int.${domain_name}"
  $base_dn = join(split($int_domain_name, '[.]').map |$dc| { "dc=${dc}" }, ',')
  $admin_password = lookup('profile::freeipa::server::admin_password')

  file { '/var/www/userportal/userportal/settings/99-local.py':
    show_diff => false,
    content   => epp('profile/userportal/99-local.py',
      {
        'password'        => $password,
        'slurm_password'  => lookup('profile::slurm::accounting::password'),
        'cluster_name'    => lookup('profile::slurm::base::cluster_name'),
        'secret_key'      => seeded_rand_string(32, $password),
        'domain_name'     => $domain_name,
        'subdomain'       => 'explore',
        'logins'          => $logins,
        'prometheus_ip'   => $prometheus_ip,
        'prometheus_port' => $prometheus_port,
        'db_ip'           => $db_ip,
        'db_port'         => $db_port,
        'base_dn'         => $base_dn,
        'ldap_password'   => $admin_password,
      }
    ),
    owner     => 'apache',
    group     => 'apache',
    mode      => '0600',
    require   => Class['profile::userportal::install_tarball'],
    notify    => [Service['httpd'], Service['gunicorn-userportal']],
  }

  file { '/var/www/userportal/userportal/local.py':
    source  => 'file:/var/www/userportal/example/local.py',
    require => Class['profile::userportal::install_tarball'],
    notify  => Service['gunicorn-userportal'],
  }

  file { '/var/www/userportal-static':
    ensure => 'directory',
    owner  => 'apache',
    group  => 'apache',
  }

  file { '/etc/httpd/conf.d/userportal.conf':
    content => epp('profile/userportal/userportal.conf.epp'),
    seltype => 'httpd_config_t',
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
    require => Class['profile::userportal::install_tarball'],
  }

  exec { 'userportal_migrate':
    command     => 'manage.py migrate',
    path        => [
      '/var/www/userportal',
      '/var/www/userportal-env/bin',
    ],
    refreshonly => true,
    subscribe   => [
      Mysql::Db['userportal'],
      Class['profile::userportal::install_tarball'],
      File['/var/www/userportal/userportal/settings/99-local.py'],
      File['/var/www/userportal/userportal/local.py'],
    ],
    notify      => Service['gunicorn-userportal'],
  }

  exec { 'userportal_collectstatic':
    command => 'manage.py collectstatic --noinput',
    path    => [
      '/var/www/userportal',
      '/var/www/userportal-env/bin',
    ],
    require => [
      File['/var/www/userportal/userportal/settings/99-local.py'],
      File['/var/www/userportal/userportal/local.py'],
      Class['profile::userportal::install_tarball'],
    ],
    creates => [
      '/var/www/userportal-static/admin',
      '/var/www/userportal-static/custom.js',
      '/var/www/userportal-static/dashboard.css',
    ],
  }

  exec { 'userportal_apiuser':
    command     => "manage.py createsuperuser --noinput --username root --email root@${domain_name}",
    path        => [
      '/var/www/userportal',
      '/var/www/userportal-env/bin',
    ],
    refreshonly => true,
    subscribe   => Exec['userportal_migrate'],
    returns     => [0, 1], # ignore error if user already exists
  }

  $api_token_command = @("EOT")
    echo 'from django.db.utils import IntegrityError
    from rest_framework.authtoken.models import Token
    try:
      Token.objects.create(user_id=1)
    except IntegrityError:
      pass
    Token.objects.filter(user_id=1).update(key="${root_api_token}")' | manage.py shell
    |EOT

  file { '/var/www/userportal/.root_api_token.hash':
    content => str2saltedsha512($root_api_token),
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
  }

  exec { 'userportal_api_token':
    command     => Sensitive($api_token_command),
    subscribe   => [
      Exec['userportal_apiuser'],
      File['/var/www/userportal/.root_api_token.hash'],
    ],
    refreshonly => true,
    path        => [
      '/var/www/userportal',
      '/var/www/userportal-env/bin',
      '/usr/bin',
    ],
  }

  mysql::db { 'userportal':
    ensure   => present,
    user     => 'userportal',
    password => $password,
    host     => 'localhost',
    grant    => ['ALL'],
  }
}

class profile::userportal::slurm_jobscripts (
  String $token
) {
  ensure_packages(['python3', 'python3-requests'])
  $slurm_jobscript_ini = @("EOT")
    [slurm]
    spool = /var/spool/slurm

    [api]
    host = http://localhost:8001
    script_length = 100000
    token = ${token}
    | EOT

  file { '/etc/slurm/slurm_jobscripts.ini':
    ensure  => 'file',
    owner   => 'slurm',
    group   => 'slurm',
    mode    => '0600',
    replace => false,
    notify  => Service['slurm_jobscripts'],
    content => $slurm_jobscript_ini,
  }

  file { '/etc/systemd/system/slurm_jobscripts.service':
    mode   => '0644',
    source => 'puppet:///modules/profile/userportal/slurm_jobscripts.service',
    notify => Service['slurm_jobscripts'],
  }

  $portal_version = lookup('profile::userportal::install_tarball::version', undef, undef, '1.0.2')
  file { '/opt/software/slurm/bin/slurm_jobscripts.py':
    mode    => '0755',
    source  => "https://raw.githubusercontent.com/guilbaults/TrailblazingTurtle/v${portal_version}/slurm_jobscripts/slurm_jobscripts.py",
    notify  => Service['slurm_jobscripts'],
    require => Package['slurm'],
  }

  service { 'slurm_jobscripts':
    ensure => 'running',
    enable => true,
  }
}

class profile::userportal::install_tarball (String $version = '1.0.2') {
  ensure_packages(['python38', 'python38-devel'])
  ensure_packages(['openldap-devel', 'gcc', 'mariadb-devel'])

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
    source          => "https://github.com/guilbaults/TrailblazingTurtle/archive/refs/tags/v${version}.tar.gz",
    creates         => '/var/www/userportal/manage.py',
    path            => '/tmp/userportal.tar.gz',
    extract         => true,
    extract_path    => '/var/www/userportal/',
    extract_command => 'tar xfz %s --strip-components=1',
    cleanup         => true,
    user            => 'apache',
    notify          => [Service['httpd'], Service['gunicorn-userportal']],
  }

  exec { 'userportal_pip':
    command     => 'pip3 install -r /var/www/userportal/requirements.txt',
    path        => [
      '/var/www/userportal-env/bin',
      '/usr/bin',
    ],
    refreshonly => true,
    subscribe   => Archive['userportal'],
    require     => [
      Exec['userportal_venv'],
      Package['python38-devel'],
      Package['mariadb-devel'],
      Package['openldap-devel'],
      Package['gcc'],
    ],
  }

  # Need to use this fork to manage is_staff correctly
  # https://github.com/enervee/django-freeipa-auth/pull/9
  -> exec { 'pip install django-freeipa-auth':
    command => 'pip3 install https://github.com/88Ocelot/django-freeipa-auth/archive/d77df67c03a5af5923116afa2f4280b8264b4b5b.zip',
    path    => [
      '/var/www/userportal-env/bin',
      '/usr/bin',
    ],
    creates => '/var/www/userportal-env/lib/python3.8/site-packages/freeipa_auth/backends.py',
    require => [Exec['userportal_venv']],
  }
}

# # podman command to run it in a container
# podman run --network=host IMAGE_ID
# podman cp 99-local.py CONTAINER_ID:/tbt/userportal/settings/99-local.py
# # podman exec CONTAINER_ID /tbt/manage.py migrate
# podman cp CONTAINER_ID:/tbt/static/custom.js /var/www/userportal-static/
# podman cp CONTAINER_ID:/tbt/static/dashboard.css /var/www/userportal-static/
# podman restart CONTAINER_ID
