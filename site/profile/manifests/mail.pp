class profile::mail::base (
  String $origin,
  Array[String] $authorized_submit_users = ['root', 'slurm'],
) {
  postfix::config { 'authorized_submit_users':
    ensure => present,
    value  => join($authorized_submit_users, ','),
  }

  file { '/etc/mailname':
    content => $origin,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    seltype => 'postfix_etc_t',
  }
}

class profile::mail {
  $relayhosts = lookup('profile::mail::sender::relayhosts')
  $ipaddress = lookup('terraform.self.local_ip')

  include profile::mail::base
  if $ipaddress in $relayhosts {
    include profile::mail::relayhost
  } else {
    include profile::mail::sender
  }
}

class profile::mail::sender (
  Array[String] $relayhosts,
) {
  $origin = lookup('profile::mail::base::origin')
  class { 'postfix':
    inet_protocols   => 'ipv4',
    relayhost        => join($relayhosts, ','),
    myorigin         => $origin,
    satellite        => true,
    manage_mailx     => false,
    manage_conffiles => false,
    manage_mailname  => false,
  }
}

class profile::mail::relayhost {
  if lookup('profile::mail::dkim::private_key', undef, undef, '') != '' {
    include profile::mail::dkim
  }

  $cidr = profile::getcidr()
  $ipaddress = lookup('terraform.self.local_ip')
  $origin = lookup('profile::mail::base::origin')

  class { 'postfix':
    inet_interfaces  => "127.0.0.1, ${ipaddress}",
    inet_protocols   => 'ipv4',
    mynetworks       => "127.0.0.0/8, ${cidr}",
    myorigin         => $origin,
    mta              => true,
    relayhost        => 'direct',
    smtp_listen      => 'all',
    manage_mailx     => false,
    manage_conffiles => false,
    manage_mailname  => false,
  }

  postfix::config { 'myhostname':
    ensure => present,
    value  => "${facts['networking']['hostname']}.${origin}",
  }
}

# profile::mail::dkim class
#
# This class manages OpenDKIM installation and service.
# It is meant to be used in conjunction with puppet::mail::relayhost.
# OpenDKIM signs emails with a private key and email providers can
# verify the email signature authenticity using the DKIM dns record.

# The class assumes the dkim public key is published as a TXT DNS record
# under default._domainkey.${domain_name}.
#
# @param dkim_private_key Private RSA key for DKIM
class profile::mail::dkim (
  String $private_key,
) {
  $domain_name = lookup('profile::mail::base::origin')
  $cidr = profile::getcidr()

  user { 'postfix':
    ensure     => present,
    groups     => ['opendkim'],
    membership => minimum,
    require    => Package['opendkim'],
  }

  package { 'opendkim':
    ensure  => 'installed',
    require => Yumrepo['epel'],
  }

  file { '/etc/opendkim/keys/default.private':
    content => $private_key,
    owner   => 'opendkim',
    group   => 'opendkim',
    mode    => '0600',
    require => Package['opendkim'],
  }

  service { 'opendkim':
    ensure  => running,
    enable  => true,
    require => [
      Package['opendkim'],
      File['/etc/opendkim/keys/default.private'],
    ],
  }

  file_line { 'opendkim-Mode':
    ensure  => present,
    path    => '/etc/opendkim.conf',
    line    => 'Mode sv',
    match   => '^Mode',
    notify  => Service['opendkim'],
    require => Package['opendkim'],
  }

  file_line { 'opendkim-Canonicalization':
    ensure  => present,
    path    => '/etc/opendkim.conf',
    line    => 'Canonicalization relaxed/simple',
    match   => '^#?Canonicalization',
    notify  => Service['opendkim'],
    require => Package['opendkim'],
  }

  file_line { 'opendkim-KeyFile':
    ensure  => present,
    path    => '/etc/opendkim.conf',
    line    => '#KeyFile /etc/opendkim/keys/default.private',
    match   => '^KeyFile',
    notify  => Service['opendkim'],
    require => Package['opendkim'],
  }

  file_line { 'opendkim-KeyTable':
    ensure  => present,
    path    => '/etc/opendkim.conf',
    line    => 'KeyTable refile:/etc/opendkim/KeyTable',
    match   => '^#?KeyTable',
    notify  => Service['opendkim'],
    require => Package['opendkim'],
  }

  file_line { 'opendkim-SigningTable':
    ensure  => present,
    path    => '/etc/opendkim.conf',
    line    => 'SigningTable refile:/etc/opendkim/SigningTable',
    match   => '^#?SigningTable',
    notify  => Service['opendkim'],
    require => Package['opendkim'],
  }

  file_line { 'opendkim-ExternalIgnoreList':
    ensure  => present,
    path    => '/etc/opendkim.conf',
    line    => 'ExternalIgnoreList refile:/etc/opendkim/TrustedHosts',
    match   => '^#?ExternalIgnoreList',
    notify  => Service['opendkim'],
    require => Package['opendkim'],
  }

  file_line { 'opendkim-InternalHosts':
    ensure  => present,
    path    => '/etc/opendkim.conf',
    line    => 'InternalHosts refile:/etc/opendkim/TrustedHosts',
    match   => '^#?InternalHosts',
    notify  => Service['opendkim'],
    require => Package['opendkim'],
  }

  file_line { 'opendkim-KeyTable-content':
    ensure  => present,
    path    => '/etc/opendkim/KeyTable',
    line    => "default._domainkey.${domain_name} ${domain_name}:default:/etc/opendkim/keys/default.private",
    notify  => Service['opendkim'],
    require => Package['opendkim'],
  }

  file_line { 'opendkim-SigningTable-content':
    ensure  => present,
    path    => '/etc/opendkim/SigningTable',
    line    => "*@${domain_name} default._domainkey.${domain_name}",
    notify  => Service['opendkim'],
    require => Package['opendkim'],
  }

  file_line { 'opendkim-TrustedHosts':
    ensure  => present,
    path    => '/etc/opendkim/TrustedHosts',
    line    => $cidr,
    notify  => Service['opendkim'],
    require => Package['opendkim'],
  }

  postfix::config { 'smtpd_milters':
    ensure => present,
    value  => 'local:/run/opendkim/opendkim.sock',
  }

  postfix::config { 'non_smtpd_milters':
    ensure => present,
    value  => '$smtpd_milters',
  }

  postfix::config { 'milter_default_action':
    ensure => present,
    value  => 'accept',
  }
}
