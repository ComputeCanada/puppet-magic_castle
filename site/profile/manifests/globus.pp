class profile::globus {
  package { 'wget':
    ensure => installed,
  }

  $public_ip = lookup('terraform.self.public_ip')
  class { 'globus':
    display_name  => $globus::display_name,
    client_id     => $globus::client_id,
    client_secret => $globus::client_secret,
    contact_email => $globus::contact_email,
    ip_address    => $public_ip,
    organization  => $globus::organization,
    owner         => $globus::owner,
    require       => Package['wget'],
  }
}
