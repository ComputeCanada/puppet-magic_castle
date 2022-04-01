class profile::reverse_proxy(
  String $domain_name,
  String $jupyterhub_subdomain,
  String $ipa_subdomain,
  String $mokey_subdomain,
  )
{
  selinux::boolean { 'httpd_can_network_connect': }

  firewall { '200 httpd public':
    chain  => 'INPUT',
    dport  => [80, 443],
    proto  => 'tcp',
    source => '0.0.0.0/0',
    action => 'accept'
  }

  yumrepo { 'caddy-copr-repo':
    enabled             => true,
    descr               => 'Copr repo for caddy',
    baseurl             => "https://download.copr.fedorainfracloud.org/results/@caddy/caddy/epel-\$releasever-\$basearch/",
    skip_if_unavailable => true,
    gpgcheck            => 1,
    gpgkey              => 'https://download.copr.fedorainfracloud.org/results/@caddy/caddy/pubkey.gpg',
    repo_gpgcheck       => 0,
  }

  package { 'caddy':
    ensure  => 'installed',
    require => Yumrepo['caddy-copr-repo']
  }

  $ipa_server_ip = lookup('profile::freeipa::client::server_ip')
  $mokey_port = lookup('profile::freeipa::mokey::port')

  file { '/etc/caddy/Caddyfile':
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => Package['caddy'],
    content => @("END")
${domain_name} {
  tls /etc/letsencrypt/live/${domain_name}/fullchain.pem /etc/letsencrypt/live/${domain_name}/privkey.pem
  redir ${jupyterhub_subdomain}.${domain_name}
}

${jupyterhub_subdomain}.${domain_name} {
  tls /etc/letsencrypt/${domain_name}/fullchain.pem /etc/letsencrypt/live/${domain_name}/privkey.pem
  reverse_proxy ${$jupyterhub::bind_url}
}

${mokey_subdomain}.${domain_name} {
  tls /etc/letsencrypt/live/${domain_name}/fullchain.pem /etc/letsencrypt/live/${domain_name}/privkey.pem
  reverse_proxy ${ipa_server_ip}:${mokey_port}
}

${ipa_subdomain}.${domain_name} {
  tls /etc/letsencrypt/live/${domain_name}/fullchain.pem /etc/letsencrypt/live/${domain_name}/privkey.pem
  reverse_proxy ${ipa_subdomain}.int.${domain_name}
}

END
  }

  service { 'caddy':
    ensure    => running,
    enable    => true,
    require   => Package['caddy'],
    subscribe => File['/etc/caddy/Caddyfile'],
  }
}
