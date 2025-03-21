class profile::reverse_proxy (
  String $domain_name,
  Hash[String, String] $subdomains,
  Hash[String, Array[String]] $remote_ips = {},
  String $main2sub_redir = 'jupyter',
  String $robots_txt = "User-agent: *\nDisallow: /",
) {
  selinux::boolean { 'httpd_can_network_connect': }

  selinux::module { 'caddy':
    ensure    => 'present',
    source_pp => 'puppet:///modules/profile/reverse_proxy/caddy.pp',
  }

  firewall { '200 httpd public':
    chain  => 'INPUT',
    dport  => [80, 443],
    proto  => 'tcp',
    source => '0.0.0.0/0',
    action => 'accept',
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
    require => Yumrepo['caddy-copr-repo'],
  }

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
    content => @("EOT"),
(tls) {
  ${tls_string}
}
import conf.d/*
| EOT
  }

  $host_conf_template = @("END")
    ${domain_name} {
      import tls
      respond /robots.txt 200 {
        body "${robots_txt}"
        close
      }
    <% if '${main2sub_redir}' != '' { -%>
      redir / https://${main2sub_redir}.${domain_name}
    <% } -%>
    }
    |END

  file { '/etc/caddy/conf.d/host.conf':
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    seltype => 'httpd_config_t',
    require => File['/etc/caddy/conf.d'],
    content => inline_epp($host_conf_template),
  }

  $subdomains.each | $key, $value | {
    file { "/etc/caddy/conf.d/${key}.conf":
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      seltype => 'httpd_config_t',
      require => File['/etc/caddy/conf.d'],
      content => epp(
        'profile/reverse_proxy/subdomain.conf',
        {
          'domain'     => $domain_name,
          'subdomain'  => $key,
          'server'     => $value,
          'remote_ip'  => $remote_ips.get($key, ''),
          'robots_txt' => $robots_txt
        }
      ),
    }
  }

  service { 'caddy':
    ensure    => running,
    enable    => true,
    require   => [
      Package['caddy'],
      Selinux::Module['caddy'],
    ],
    subscribe => [
      File['/etc/caddy/Caddyfile'],
      File['/etc/caddy/conf.d/host.conf'],
    ] + $subdomains.map |$key, $value| { File["/etc/caddy/conf.d/${key}.conf"] },
  }
}
