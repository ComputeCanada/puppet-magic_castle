class profile::puppetserver {
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
}
