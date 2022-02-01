class profile::base (
  Optional[String] $admin_email = undef,
) {
  include stdlib
  include ::consul_template
  include epel

  if dig($::facts, 'os', 'release', 'major') == '8' {
    exec { 'enable_powertools':
      command => 'dnf config-manager --set-enabled powertools',
      unless  => 'dnf config-manager --dump powertools | grep -q \'enabled = 1\'',
      path    => ['/usr/bin']
    }
  }

  if dig($::facts, 'os', 'release', 'major') == '7' {
    package { 'yum-plugin-priorities':
      ensure => 'installed'
    }
  }

  file { '/etc/localtime':
    ensure => link,
    target => '/usr/share/zoneinfo/UTC',
  }

  if $admin_email {
    include profile::mail::server
    file { '/opt/puppetlabs/bin/postrun':
      ensure  => present,
      mode    => '0700',
      content => epp('profile/base/postrun', {
        'email' => $admin_email,
      }),
    }
  }

  # Allow users to run TCP servers - activated to allow users
  # to run mpi jobs.
  selinux::boolean { 'selinuxuser_tcp_server': }

  file { '/etc/puppetlabs/puppet/csr_attributes.yaml':
    ensure => absent
  }

  class { 'selinux':
    mode => 'enforcing',
    type => 'targeted',
  }

  class { '::swap_file':
    files => {
      '/mnt/swap' => {
        ensure       => present,
        swapfile     => '/mnt/swap',
        swapfilesize => '1 GB',
      },
    },
  }

  package { 'pciutils':
    ensure => 'installed'
  }

  package { 'vim':
    ensure => 'installed'
  }

  package { 'unzip':
    ensure => 'installed'
  }

  package { 'firewalld':
    ensure => 'absent',
  }

  class { 'firewall': }

  firewall { '001 accept all from local network':
    chain  => 'INPUT',
    proto  => 'all',
    source => profile::getcidr(),
    action => 'accept'
  }

  firewall { '001 drop access to metadata server':
    chain       => 'OUTPUT',
    proto       => 'tcp',
    destination => '169.254.169.254',
    action      => 'drop',
    uid         => '! root'
  }

  package { 'haveged':
    ensure  => 'installed',
    require => Yumrepo['epel']
  }

  package { 'clustershell':
    ensure  => 'installed',
    require => Yumrepo['epel']
  }

  service { 'haveged':
    ensure  => running,
    enable  => true,
    require => Package['haveged']
  }

  package { 'xauth':
    ensure => 'installed'
  }

  service { 'sshd':
    ensure => running,
    enable => true,
  }

  sshd_config { 'PermitRootLogin':
    ensure => present,
    value  => 'no',
    notify => Service['sshd']
  }

  file_line { 'MACs':
    ensure => present,
    path   => '/etc/ssh/sshd_config',
    line   => 'MACs umac-128-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com',
    notify => Service['sshd']
  }

  file_line { 'KexAlgorithms':
    ensure => present,
    path   => '/etc/ssh/sshd_config',
    line   => 'KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org',
    notify => Service['sshd']
  }

  file_line { 'HostKeyAlgorithms':
    ensure => present,
    path   => '/etc/ssh/sshd_config',
    line   => 'HostKeyAlgorithms ssh-rsa',
    notify => Service['sshd']
  }

  file_line { 'Ciphers':
    ensure => present,
    path   => '/etc/ssh/sshd_config',
    line   => 'Ciphers chacha20-poly1305@openssh.com,aes128-ctr,aes192-ctr,aes256-ctr,aes128-gcm@openssh.com,aes256-gcm@openssh.com',
    notify => Service['sshd']
  }

  if $::facts.dig('cloud', 'provider') == 'azure' {
    include profile::base::azure
  }

  # Remove scripts leftover by terraform remote-exec provisioner
  file { glob('/tmp/terraform_*.sh'):
    ensure => absent
  }

  $mc_plugins_version = '1.0.3'
  package { 'magic_castle-plugins':
    ensure   => 'latest',
    name     => 'magic_castle-plugins',
    provider => 'rpm',
    source   => "https://github.com/computecanada/magic_castle-plugins/releases/download/v${mc_plugins_version}/magic_castle-plugins-${mc_plugins_version}-1.${::facts['os']['architecture']}.rpm",
  }
}

class profile::base::azure {
  package { 'WALinuxAgent':
    ensure => purged,
  }

  file { '/etc/udev/rules.d/66-azure-storage.rules':
    ensure         => 'present',
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
