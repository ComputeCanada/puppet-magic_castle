class profile::software_stack (
  Integer $min_uid = 1000,
  Optional[String] $initial_profile = undef,
  Optional[Array[String]] $lmod_default_modules = undef,
  Optional[Hash[String, String]] $extra_site_env_vars = undef,
  Optional[Pattern[/\A\d{4}(\.\d{2})?\z/]] $version = undef,
) {
  include profile::consul
  include profile::cvmfs::client

  $stack_name = $facts['software_stack'] ? {
    'computecanada' => 'computecanada',
    'alliance'      => 'computecanada',
    'eessi'         => 'eessi',
    default         => undef,
  }

  package { 'cvmfs-config-default':
    ensure  => installed,
    require => Yumrepo['cvmfs-repo'],
  }

  if $stack_name == 'computecanada' {
    $repositories = lookup('profile::cvmfs::client::repositories', undef, undef, [])
    if 'cvmfs-config.computecanada.ca' in $repositories {
      package { 'cvmfs-config-computecanada':
        ensure   => 'installed',
        provider => 'rpm',
        require  => Package['cvmfs'],
        source   => 'https://git.computecanada.ca/cc-cvmfs-public/cvmfs-config/-/raw/master/prod/RPM/cvmfs-config-computecanada-2.1.0-1.noarch.rpm',
      }
    }

    if $facts['os']['architecture'] != 'x86_64' {
      fail("${facts['software_stack']} software stack does not support: ${facts['os']['architecture']}")
    }

    file { '/etc/consul-template/z-00-rsnt_arch.sh.ctmpl':
      source => 'puppet:///modules/profile/software_stack/z-00-rsnt_arch.sh.ctmpl',
      notify => Service['consul-template'],
    }

    consul_template::watch { 'z-00-rsnt_arch.sh':
      require     => File['/etc/consul-template/z-00-rsnt_arch.sh.ctmpl'],
      config_hash => {
        perms       => '0644',
        source      => '/etc/consul-template/z-00-rsnt_arch.sh.ctmpl',
        destination => '/etc/profile.d/z-00-rsnt_arch.sh',
        command     => '/usr/bin/true',
      },
    }
    $software_stack_meta = { arch => $facts['cpu_ext'] }
  }
  if $stack_name == 'eessi' {
    if $version {
      $software_stack_meta = { 'version' => $version }
    } else {
      $software_stack_meta = {}
    }
  }

  $ensure_stack = $stack_name ? {
    'computecanada' => 'present',
    'eessi'         => 'present',
    default         => 'absent',
  }
  $ensure_rsnt_arch = $stack_name ? {
    'computecanada' => 'present',
    default         => 'absent'
  }

  file { '/etc/profile.d/z-00-rsnt_arch.sh':
    ensure => $ensure_rsnt_arch,
  }

  file { '/etc/profile.d/z-01-site.sh':
    ensure  => $ensure_stack,
    content => epp('profile/software_stack/z-01-site.sh',
      {
        'min_uid'              => $min_uid,
        'lmod_default_modules' => $lmod_default_modules,
        'initial_profile'      => $initial_profile,
        'extra_site_env_vars'  => $extra_site_env_vars,
      }
    ),
  }

  @consul::service { 'software_stack':
    ensure => $ensure_stack,
    meta   => $software_stack_meta,
  }
}
