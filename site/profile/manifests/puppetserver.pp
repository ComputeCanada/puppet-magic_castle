class profile::puppetserver (
  Integer $jruby_max_active_instances = 1,
  Integer $java_heap_size = 1024,
) {
  $eyaml_path = '/opt/puppetlabs/puppet/bin/eyaml'
  $boot_private_key_path = '/etc/puppetlabs/puppet/eyaml/boot_private_key.pkcs7.pem'
  $boot_eyaml = '/etc/puppetlabs/code/environments/production/data/bootstrap.yaml'
  $local_users = lookup('profile::users::local::users', undef, undef, {})
  $local_users.each | $user, $attrs | {
    if pick($attrs['sudoer'], false) {
      file_line { "${user}_eyamlbootstrap":
        path    => "/${user}/.bashrc",
        line    => "alias eyamlbootstrap=\"sudo ${eyaml_path} decrypt --pkcs7-private-key ${boot_private_key_path} -f ${boot_eyaml} | less\"",
        require => User[$user],
      }
    }
  }

  file_line { 'puppetserver_java_heap_size':
    path   => '/etc/sysconfig/puppetserver',
    match  => '^JAVA_ARGS=',
    line   => "JAVA_ARGS=\"-Xms${java_heap_size}m -Xmx${java_heap_size}m -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger\"", #lint:ignore:140chars
    notify => Service['puppetserver'],
    tag    => ['mc_bootstrap'],
  }

  file_line { 'puppetserver_max_active_instances':
    path   => '/etc/puppetlabs/puppetserver/conf.d/puppetserver.conf',
    match  => '^    #max-active-instances:',
    line   => "    max-active-instances: ${jruby_max_active_instances}",
    notify => Service['puppetserver'],
    tag    => ['mc_bootstrap'],
  }

  file { '/etc/puppetlabs/puppet/prometheus.yaml':
    owner   => 'root',
    group   => 'root',
    content => "---\ntextfile_directory: /var/lib/node_exporter",
    tag     => ['mc_bootstrap'],
  }

  @user { 'puppet':
    ensure => present,
    notify => Service['puppetserver'],
  }

  service { 'puppetserver':
    ensure => running,
    enable => true,
  }

  include profile::firewall
  include nftables::rules::puppet
}
