class profile::base (
  String $version,
  Optional[String] $admin_email = undef,
) {
  include stdlib
  include epel
  include selinux
  include profile::base::etc_hosts
  include profile::base::powertools
  include profile::ssh::base

  file { '/etc/magic-castle-release':
    content => "Magic Castle release ${version}",
  }

  file { '/usr/sbin/prepare4image.sh':
    source => 'puppet:///modules/profile/base/prepare4image.sh',
    mode   => '0755',
  }

  if dig($::facts, 'os', 'release', 'major') == '7' {
    package { 'yum-plugin-priorities':
      ensure => 'installed',
    }
  }

  file { '/etc/localtime':
    ensure => link,
    target => '/usr/share/zoneinfo/UTC',
  }

  if $admin_email {
    include profile::mail::server
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

  class { 'firewall': }

  firewall { '001 accept all from local network':
    chain  => 'INPUT',
    proto  => 'all',
    source => profile::getcidr(),
    action => 'accept',
  }

  firewall { '001 drop access to metadata server':
    chain       => 'OUTPUT',
    proto       => 'tcp',
    destination => '169.254.169.254',
    action      => 'drop',
    uid         => '! root',
  }

  package { 'haveged':
    ensure  => 'installed',
    require => Yumrepo['epel'],
  }

  package { 'clustershell':
    ensure  => 'installed',
    require => Yumrepo['epel'],
  }

  service { 'haveged':
    ensure  => running,
    enable  => true,
    require => Package['haveged'],
  }

  if $::facts.dig('cloud', 'provider') == 'azure' {
    include profile::base::azure
  }

  # Remove scripts leftover by terraform remote-exec provisioner
  file { glob('/tmp/terraform_*.sh'):
    ensure => absent,
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
  $domain_name = lookup('profile::freeipa::base::domain_name')
  $int_domain_name = "int.${domain_name}"
  $hostname = $facts['networking']['hostname']
  $fqdn = "${hostname}.${int_domain_name}"
  $interface = profile::getlocalinterface()
  $ipaddress = $facts['networking']['interfaces'][$interface]['ip']

  # build /etc/hosts
  # Make sure /etc/hosts entry for the current host is managed by Puppet or
  # that at least it is in entered in the right format.
  exec { 'sed_fqdn':
    command => "sed -i '/^${ipaddress}\\s/d' /etc/hosts",
    unless  => "grep -E '^${ipaddress}\\s+${fqdn}\\s+${hostname}$' /etc/hosts",
    path    => ['/bin'],
  }

  $instances = lookup('terraform.instances')
  $hosts_to_add = Hash($instances.map |$k, $v| {
      [
        "${k}.${int_domain_name}",
        {
          ip           => $v['local_ip'],
          host_aliases => [$k],
          require      => Exec['sed_fqdn'],
          before       => Exec['sed_host_wo_fqdn'],
        }
      ]
    }
  )
  ensure_resources('host', $hosts_to_add)

  exec { 'sed_host_wo_fqdn':
    command => 'sed -i -E "/^[0-9]{1,3}(\\.[0-9]{1,3}){3}\\s+[a-z0-9-]+$/d" /etc/hosts',
    onlyif  => 'grep -E "^([0-9]{1,3}[\\.]){3}[0-9]{1,3}\\s+[a-z0-9-]+$" /etc/hosts',
    path    => ['/bin'],
  }
}

class profile::base::powertools {
  if dig($::facts, 'os', 'release', 'major') == '8' {
    exec { 'enable_powertools':
      command => 'dnf config-manager --set-enabled powertools',
      unless  => 'dnf config-manager --dump powertools | grep -q \'enabled = 1\'',
      path    => ['/usr/bin'],
    }
  } else {
    exec { 'enable_powertools':
      command     => '/bin/true',
      refreshonly => true,
    }
  }
}
