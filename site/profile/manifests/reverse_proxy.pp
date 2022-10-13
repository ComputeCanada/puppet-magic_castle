class profile::reverse_proxy(
  String $domain_name,
  String $jupyterhub_subdomain,
  String $ipa_subdomain,
  String $mokey_subdomain,
  String $userportal_subdomain,
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

  if $domain_name in $::facts['letsencrypt'] {
    $fullchain_exists = $::facts['letsencrypt'][$domain_name]['fullchain']
    $privkey_exists = $::facts['letsencrypt'][$domain_name]['privkey']
  } else {
    $fullchain_exists = false
    $privkey_exists = false
  }

  $configure_tls = ($privkey_exists and $fullchain_exists)

  if $privkey_exists {
    file { "/etc/letsencrypt/live/${domain_name}/privkey.pem":
      ensure  => present,
      owner   => 'root',
      group   => 'caddy',
      mode    => '0640',
      links   => 'follow',
      require => Package['caddy'],
      before  => Service['caddy'],
    }
  }

  if $configure_tls {
    $tls_string = "tls /etc/letsencrypt/live/${domain_name}/fullchain.pem /etc/letsencrypt/live/${domain_name}/privkey.pem"
  } else {
    $tls_string = ''
  }

  file { '/etc/caddy/conf.d':
    ensure  => directory,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    seltype => 'httpd_config_t',
    require => Package['caddy'],
  }

  file { '/etc/caddy/Caddyfile':
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    seltype => 'httpd_config_t',
    require => Package['caddy'],
    content => @("END")
(tls) {
  ${tls_string}
}
import conf.d/*
END
  }

  file { '/etc/caddy/conf.d/host.conf':
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    seltype => 'httpd_config_t',
    require => File['/etc/caddy/conf.d'],
    content => @("END")
${domain_name} {
  import tls
  redir https://${jupyterhub_subdomain}.${domain_name}
}
END
  }

  file { '/etc/caddy/conf.d/jupyter.conf':
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    seltype => 'httpd_config_t',
    require => File['/etc/caddy/conf.d'],
    content => @("END")
${jupyterhub_subdomain}.${domain_name} {
  import tls
  reverse_proxy ${$jupyterhub::bind_url} {
    transport http {
      tls_insecure_skip_verify
    }
  }
}
END
  }

  file { '/etc/caddy/conf.d/mokey.conf':
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    seltype => 'httpd_config_t',
    require => File['/etc/caddy/conf.d'],
    content => @("END")
${mokey_subdomain}.${domain_name} {
  import tls
  reverse_proxy ${ipa_server_ip}:${mokey_port}
}
END
  }

  file { '/etc/caddy/conf.d/ipa.conf':
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    seltype => 'httpd_config_t',
    require => File['/etc/caddy/conf.d'],
    content => @("END")
${ipa_subdomain}.${domain_name} {
  import tls
  reverse_proxy ${ipa_subdomain}.int.${domain_name}
}
END
  }

  # The django userportal is hosted on the same apache server as FreeIPA, but on port 9000
  file { '/etc/caddy/conf.d/userportal.conf':
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    seltype => 'httpd_config_t',
    require => File['/etc/caddy/conf.d'],
    content => @("END")
${userportal_subdomain}.${domain_name} {
  import tls
  reverse_proxy ${ipa_subdomain}.int.${domain_name}:9000
}
END
  }

  service { 'caddy':
    ensure    => running,
    enable    => true,
    require   => [
      Package['caddy'],
    ],
    subscribe => [
      File['/etc/caddy/Caddyfile'],
      File['/etc/caddy/conf.d/host.conf'],
      File['/etc/caddy/conf.d/jupyter.conf'],
      File['/etc/caddy/conf.d/mokey.conf'],
      File['/etc/caddy/conf.d/ipa.conf'],
      File['/etc/caddy/conf.d/userportal.conf'],
    ]
  }
}
