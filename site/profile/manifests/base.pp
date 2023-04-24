class profile::base (
  String $version,
  Optional[String] $admin_email = undef,
) {
  include stdlib
  include consul_template
  include epel
  include selinux

  $domain_name = lookup('profile::freeipa::base::domain_name')
  $int_domain_name = "int.${domain_name}"
  $hostname = $facts['networking']['hostname']
  $fqdn = "${hostname}.${int_domain_name}"
  $interface = $facts['networking']['primary']
  $ipaddress = $facts['networking']['interfaces'][$interface]['ip']

  file { '/etc/magic-castle-release':
    content => "Magic Castle release ${version}",
  }

  # Ensure consul can read the state of agent_catalog_run.lock
  file { '/opt/puppetlabs/puppet/cache':
    ensure => directory,
    mode   => '0751',
  }

  file { '/usr/sbin/prepare4image.sh':
    source => 'puppet:///modules/profile/base/prepare4image.sh',
    mode   => '0755',
  }

  if dig($::facts, 'os', 'release', 'major') == '8' {
    exec { 'enable_powertools':
      command => 'dnf config-manager --set-enabled powertools',
      unless  => 'dnf config-manager --dump powertools | grep -q \'enabled = 1\'',
      path    => ['/usr/bin'],
    }
  }

  # build /etc/hosts
  # Make sure /etc/hosts entry for the current host is manage by Puppet only
  exec { 'sed_fqdn':
    command => "sed -i '/^${ipaddress}/d' /etc/hosts",
    onlyif  => "grep '${ipaddress}' /etc/hosts | grep -v -E '${fqdn}\\s+${hostname}'",
    path    => ['/bin'],
  }

  $instances = lookup('terraform.instances')
  $hosts_to_add = Hash($instances.map |$k, $v| {
      [
        "${k}.${int_domain_name}",
        {
          ip           => $v['local_ip'],
          host_aliases => [$k] + ('puppet' in $v['tags'] ? { true => ['puppet'], false => [] }),
          require      => Exec['sed_fqdn'],
          before       => Exec['sed_host_puppet'],
        }
      ]
    }
  )
  ensure_resources('host', $hosts_to_add)

  exec { 'sed_host_puppet':
    command => 'sed -i -E "/^[0-9]{1,3}(\\.[0-9]{1,3}){3}\\s+puppet$/d" /etc/hosts',
    onlyif  => 'grep -E "^([0-9]{1,3}[\\.]){3}[0-9]{1,3}\\s+puppet$" /etc/hosts',
    path    => ['/bin'],
  }

  # building /etc/ssh/ssh_known_hosts
  # for host based authentication
  $type = 'ed25519'
  $sshkey_to_add = Hash(
    $instances.map |$k, $v| {
      [
        $k,
        {
          'key' => split($v['hostkeys'][$type], /\s/)[1],
          'type' => "ssh-${type}",
          'host_aliases' => ["${k}.${int_domain_name}", $v['local_ip'],]
        }
      ]
  })
  ensure_resources('sshkey', $sshkey_to_add)

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

  class { 'swap_file':
    files => {
      '/mnt/swap' => {
        ensure       => present,
        swapfile     => '/mnt/swap',
        swapfilesize => '1 GB',
      },
    },
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

  package { 'xauth':
    ensure => 'installed',
  }

  service { 'sshd':
    ensure => running,
    enable => true,
  }

  sshd_config { 'PermitRootLogin':
    ensure => present,
    value  => 'no',
    notify => Service['sshd'],
  }

  file_line { 'MACs':
    ensure => present,
    path   => '/etc/ssh/sshd_config',
    line   => 'MACs umac-128-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com',
    notify => Service['sshd'],
  }

  file_line { 'KexAlgorithms':
    ensure => present,
    path   => '/etc/ssh/sshd_config',
    line   => 'KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org',
    notify => Service['sshd'],
  }

  file_line { 'HostKeyAlgorithms':
    ensure => present,
    path   => '/etc/ssh/sshd_config',
    line   => 'HostKeyAlgorithms ssh-rsa',
    notify => Service['sshd'],
  }

  file_line { 'Ciphers':
    ensure => present,
    path   => '/etc/ssh/sshd_config',
    line   => 'Ciphers chacha20-poly1305@openssh.com,aes128-ctr,aes192-ctr,aes256-ctr,aes128-gcm@openssh.com,aes256-gcm@openssh.com',
    notify => Service['sshd'],
  }

  file { '/etc/ssh/ssh_host_ed25519_key':
    mode  => '0640',
    owner => 'root',
    group => 'ssh_keys',
  }

  file { '/etc/ssh/ssh_host_ed25519_key.pub':
    mode  => '0644',
    owner => 'root',
    group => 'ssh_keys',
  }

  file { '/etc/ssh/ssh_host_rsa_key':
    mode  => '0640',
    owner => 'root',
    group => 'ssh_keys',
  }

  file { '/etc/ssh/ssh_host_rsa_key.pub':
    mode  => '0644',
    owner => 'root',
    group => 'ssh_keys',
  }

  if dig($::facts, 'os', 'release', 'major') == '8' {
    # sshd hardening in CentOS 8 requires fidgetting with crypto-policies
    # instead of modifying /etc/ssh/sshd_config
    # https://sshaudit.com/hardening_guides.html#rhel8
    # We replace the file in /usr/share/crypto-policies instead of
    # /etc/crypto-policies as suggested by sshaudit.com, because the script
    # update-crypto-policies can be called by RPM scripts and overwrites the
    # config in /etc by what's in /usr/share. The files in /etc/crypto-policies
    # are in just symlinks to /usr/share
    file { '/usr/share/crypto-policies/DEFAULT/opensshserver.txt':
      source => 'puppet:///modules/profile/base/opensshserver.config',
      notify => Service['sshd'],
    }
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
