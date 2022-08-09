# Slurm accouting. This is where slurm accounting database and daemon is ran.
# @param password Specifies the password to access the MySQL database with user slurm.
# @param dbd_port Specfies the port on which run the slurmdbd daemon.
class profile::slurm::accounting (String $password, Integer $dbd_port = 6819) {
  consul::service { 'slurmdbd':
    port    => $dbd_port,
    require => Tcp_conn_validator['consul'],
    token   => lookup('profile::consul::acl_api_token'),
  }

  $override_options = {
    'mysqld' => {
      'innodb_buffer_pool_size' => '1024M',
      'innodb_log_file_size' => '64M',
      'innodb_lock_wait_timeout' => '900',
    },
  }

  class { 'mysql::server':
    remove_default_accounts => true,
    override_options        => $override_options,
  }

  mysql::db { 'slurm_acct_db':
    ensure   => present,
    user     => 'slurm',
    password => $password,
    host     => 'localhost',
    grant    => ['ALL'],
  }

  file { '/etc/slurm/slurmdbd.conf':
    content => epp('profile/slurm/slurmdbd.conf',
      { 'dbd_host'     => $facts['networking']['hostname'],
        'dbd_port'     => $dbd_port,
        'storage_pass' => $password
      }
    ),
    owner   => 'slurm',
    mode    => '0600',
  }

  package { 'slurm-slurmdbd':
    ensure  => present,
    require => [
      Package['munge'],
      Yumrepo['slurm-copr-repo']
    ],
  }

  service { 'slurmdbd':
    ensure  => running,
    enable  => true,
    require => [
      Package['slurm-slurmdbd'],
      File['/etc/slurm/slurmdbd.conf'],
      Mysql::Db['slurm_acct_db']
    ],
    before  => Service['slurmctld'],
  }

  wait_for { 'slurmdbd_started':
    query             => 'cat /var/log/slurm/slurmdbd.log',
    regex             => '^\[[.:0-9\-T]{23}\] slurmdbd version \d+.\d+.\d+ started$',
    polling_frequency => 10,  # Wait up to 4 minutes (24 * 10 seconds).
    max_retries       => 24,
    refreshonly       => true,
    subscribe         => Service['slurmdbd'],
  }

  $cluster_name = lookup('profile::slurm::base::cluster_name')
  exec { 'sacctmgr_add_cluster':
    command   => "sacctmgr add cluster ${cluster_name} -i | grep -qP '(already exists|Adding Cluster)'",
    path      => ['/bin', '/usr/sbin', '/opt/software/slurm/bin', '/opt/software/slurm/sbin'],
    unless    => "test `sacctmgr show cluster Names=${cluster_name} -n | wc -l` == 1",
    tries     => 4,
    try_sleep => 15,
    timeout   => 15,
    require   => [
      Service['slurmdbd'],
      Wait_for['slurmdbd_started'],
      Wait_for['slurmctldhost_set'],
    ],
    before    => [
      Service['slurmctld']
    ],
  }

  logrotate::rule { 'slurmdbd':
    path         => '/var/log/slurm/slurmdbd.log',
    rotate       => 5,
    ifempty      => false,
    copytruncate => false,
    olddir       => false,
    size         => '5M',
    compress     => true,
    create       => true,
    create_mode  => '0600',
    create_owner => 'slurm',
    create_group => 'slurm',
    postrotate   => '/usr/bin/pkill -x --signal SIGUSR2 slurmdbd',
  }
}
