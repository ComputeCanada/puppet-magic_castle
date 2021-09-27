class profile::mail::base {
  $cidr = profile::getcidr()

  postfix::config { 'authorized_submit_users':
    ensure => present,
    value  => 'root, slurm',
  }

  firewall { '002 drop IPA user access to local smtp server':
    chain       => 'OUTPUT',
    proto       => 'tcp',
    dport       => [25],
    destination => '127.0.0.0/8',
    action      => 'drop',
    uid         => "! 0-${facts['uid_max']}"
  }

  firewall { '002 drop IPA user access to internal smtp server':
    chain       => 'OUTPUT',
    proto       => 'tcp',
    dport       => [25],
    destination => $cidr,
    action      => 'drop',
    uid         => "! 0-${facts['uid_max']}"
  }
}

class profile::mail::sender(
  String $relayhost_ip,
  String $origin,
) {
  include profile::mail::base
  class { 'postfix':
    inet_protocols   => 'ipv4',
    relayhost        => $relayhost_ip,
    myorigin         => $origin,
    satellite        => true,
    manage_mailx     => false,
    manage_conffiles => false,
  }
}

class profile::mail::relayhost(
  String $origin,
) {
  include profile::mail::base
  class { 'profile::mail::dkim':
    domain_name => $origin,
  }

  $cidr = profile::getcidr()
  $interface = split($::interfaces, ',')[0]
  $ipaddress = $::networking['interfaces'][$interface]['ip']

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
  }
}


# profile::mail::dkim class
#
# This class manages OpenDKIM installation and service.
# It is meant to be used in conjunction with puppet:mail::relayhost.
# OpenDKIM signs emails with a private key and email providers can
# verify the email signature authenticity using the DKIM dns record.

# That the class assumes the private keys exists in /etc/opendkim/keys/default.private.
# The class also assumes the corresponding public key is published as a TXT DNS record
# under default._domainkey.${domain_name}.
#
# @example Declaring the class
#   class { 'profile::mail::dkim':
#     domain_name => mycluster.mydomain.tld
#   }
#
# @param domain_name Domain name from which the cluster will send emails.
class profile::mail::dkim (
  String $domain_name
) {
  $cidr = profile::getcidr()

  package { 'opendkim':
    ensure  => 'installed',
    require => Yumrepo['epel'],
  }

  file { '/etc/opendkim/keys/default.private':
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
    value  => 'inet:127.0.0.1:8891',
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
