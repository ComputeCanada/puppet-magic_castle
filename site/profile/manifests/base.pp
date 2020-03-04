class profile::base (String $sudoer_username = 'centos') {
  include stdlib

  file { '/etc/localtime':
    ensure => link,
    target => '/usr/share/zoneinfo/UTC',
  }

  class { '::consul_template':
    config_hash => {
      'consul' => {
        'token' => lookup('profile::consul::acl_api_token')
      }
    },
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

  # Configure sudoer_username user selinux mapping
  exec { 'selinux_login_sudoer':
    command => "semanage login -a -S targeted -s 'unconfined_u' -r 's0-s0:c0.c1023' ${sudoer_username}",
    unless  => "grep -q '${sudoer_username}:unconfined_u:s0-s0:c0.c1023' /etc/selinux/targeted/seusers",
    path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
  }

  package { 'yum-plugin-priorities':
    ensure => 'installed'
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

  yumrepo { 'epel':
    baseurl        => 'http://dl.fedoraproject.org/pub/epel/$releasever/$basearch',
    enabled        => true,
    failovermethod => 'priority',
    gpgcheck       => false,
    gpgkey         => 'file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL',
    descr          => 'Extra Packages for Enterprise Linux'
  }

  package { 'haveged':
    ensure  => 'installed',
    require => Yumrepo['epel']
  }

  package { 'pdsh':
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

}
