class profile::base (
  String $version,
  Array[String] $packages,
  Optional[String] $admin_email = undef,
) {
  include stdlib
  include epel
  include selinux
  include profile::base::etc_hosts
  include profile::base::powertools
  include profile::ssh::base

  package { 'selinux-policy': }
  Package['selinux-policy'] -> Class['selinux::config']

  file { '/etc/magic-castle-release':
    content => "Magic Castle release ${version}",
  }

  file { '/usr/sbin/prepare4image.sh':
    source => 'puppet:///modules/profile/base/prepare4image.sh',
    mode   => '0755',
  }

  file { '/etc/localtime':
    ensure => link,
    target => '/usr/share/zoneinfo/UTC',
  }

  if $admin_email {
    file { '/opt/puppetlabs/bin/postrun':
      mode    => '0700',
      content => epp('profile/base/postrun',
        {
          'email' => $admin_email,
        }
      ),
    }
  }

  # Allow users to run TCP servers - activated to allow users
  # to run mpi jobs.
  selinux::boolean { 'selinuxuser_tcp_server': }

  file { '/etc/puppetlabs/puppet/csr_attributes.yaml':
    ensure => absent,
  }

  package { 'pciutils':
    ensure => 'installed',
  }

  package { 'vim':
    ensure => 'installed',
  }

  package { 'unzip':
    ensure => 'installed',
  }

  package { 'firewalld':
    ensure => 'absent',
  }

  class { 'firewall':
    tag => 'mc_bootstrap',
  }

  # Sometimes systemd-tmpfiles-setup.service fails to create
  # /run/lock/subsys folder which is required by iptables.
  # This exec runs the command that should have created the folder
  # if it is missing.
  exec { 'systemd-tmpfiles --create --prefix=/run/lock/subsys':
    unless => 'test -d /run/lock/subsys',
    path   => ['/bin'],
    notify => [Service['iptables'], Service['ip6tables']],
  }

  firewall { '001 accept all from local network':
    chain  => 'INPUT',
    proto  => 'all',
    source => profile::getcidr(),
    action => 'accept',
    tag    => 'mc_bootstrap',
  }

  firewall { '001 drop access to metadata server':
    chain       => 'OUTPUT',
    proto       => 'tcp',
    destination => '169.254.169.254',
    action      => 'drop',
    uid         => '! root',
    tag         => 'mc_bootstrap',
  }

  package { 'clustershell':
    ensure  => 'installed',
    require => Yumrepo['epel'],
  }

  if versioncmp($::facts['os']['release']['major'], '8') == 0 {
    # haveged service is no longer required for kernel >= 5.4
    # RHEL 8 is the last release with a kernel < 5
    package { 'haveged':
      ensure  => 'installed',
      require => Yumrepo['epel'],
    }

    service { 'haveged':
      ensure  => running,
      enable  => true,
      require => Package['haveged'],
    }
  }

  stdlib::ensure_packages($packages, { ensure => 'installed', require => Yumrepo['epel'] })

  if $::facts.dig('cloud', 'provider') == 'azure' {
    include profile::base::azure
  }

  # Remove scripts leftover by terraform remote-exec provisioner
  file { glob('/tmp/terraform_*.sh'):
    ensure => absent,
  }

  if !($facts['virtual'] =~ /^(container|lxc).*$/) {
    sysctl { 'kernel.dmesg_restrict':
      ensure => 'present',
      value  => 1,
    }
  }
}

class profile::base::azure {
  package { 'WALinuxAgent':
    ensure => purged,
  }

  file { '/etc/udev/rules.d/66-azure-storage.rules':
    source         => 'https://raw.githubusercontent.com/Azure/WALinuxAgent/v2.2.48.1/config/66-azure-storage.rules',
    require        => Package['WALinuxAgent'],
    owner          => 'root',
    group          => 'root',
    mode           => '0644',
    checksum       => 'md5',
    checksum_value => '51e26bfa04737fc1e1f14cbc8aeebece',
  }

  exec { 'udevadm trigger --action=change':
    refreshonly => true,
    subscribe   => File['/etc/udev/rules.d/66-azure-storage.rules'],
    path        => ['/usr/bin'],
  }
}

# build /etc/hosts
class profile::base::etc_hosts {
  $ipa_domain = lookup('profile::freeipa::base::ipa_domain')
  $instances = lookup('terraform.instances')

  # build /etc/hosts
  # Make sure /etc/hosts entry for the current host is managed by Puppet or
  # that at least it is in entered in the right format.
  file { '/etc/hosts':
    mode    => '0644',
    content => epp('profile/base/hosts',
      {
        'instances'       => $instances,
        'int_domain_name' => $ipa_domain,
      }
    ),
  }
}

class profile::base::powertools {
  if versioncmp($::facts['os']['release']['major'], '8') == 0 {
    $repo_name = 'powertools'
  } else {
    $repo_name = 'crb'
  }
  package { 'dnf-plugins-core': }
  exec { 'enable_powertools':
    command => "dnf config-manager --set-enabled ${$repo_name}",
    unless  => "dnf config-manager --dump ${repo_name} | grep -q \'enabled = 1\'",
    path    => ['/usr/bin'],
    require => Package['dnf-plugins-core'],
  }
}
