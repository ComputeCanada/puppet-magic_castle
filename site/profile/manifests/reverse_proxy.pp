class profile::reverse_proxy(String $domain_name)
{
  selinux::boolean { 'httpd_can_network_connect': }

  class { 'apache':
    default_vhost => false,
    servername    => $domain_name,
  }

  class { 'apache::mod::ssl':
    ssl_compression      => false,
    ssl_cipher           => 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384',
    ssl_protocol         => ['all', '-SSLv3', '-TLSv1', '-TLSv1.1'],
    ssl_honorcipherorder => false,
    ssl_ca               => "/etc/letsencrypt/live/${domain_name}/chain.pem",
  }

  include apache::mod::proxy_wstunnel

  firewall { '200 httpd public':
    chain  => 'INPUT',
    dport  => [80, 443],
    proto  => 'tcp',
    source => '0.0.0.0/0',
    action => 'accept'
  }

  apache::vhost { 'domain_to_jupyter_non_ssl':
    servername      => $domain_name,
    port            => '80',
    redirect_status => 'permanent',
    redirect_dest   => "https://jupyter.${domain_name}/",
    docroot         => false,
    manage_docroot  => false,
    access_log      => false,
    error_log       => false,
    priority        => 99,
  }

  apache::vhost { 'domain_to_jupyter_ssl':
    servername      => $domain_name,
    port            => '443',
    redirect_status => 'permanent',
    redirect_dest   => "https://jupyter.${domain_name}/",
    docroot         => false,
    manage_docroot  => false,
    access_log      => false,
    error_log       => false,
    ssl             => true,
    ssl_cert        => "/etc/letsencrypt/live/${domain_name}/fullchain.pem",
    ssl_key         => "/etc/letsencrypt/live/${domain_name}/privkey.pem",
    priority        => 99,
  }

  apache::vhost { 'jupyter80_to_jupyter443':
    servername      => "jupyter.${domain_name}",
    port            => '80',
    redirect_status => 'permanent',
    redirect_dest   => "https://jupyter.${domain_name}/",
    docroot         => false,
    manage_docroot  => false,
    access_log      => false,
    error_log       => false,
  }

  apache::vhost { 'jupyter_ssl':
    servername                => "jupyter.${domain_name}",
    port                      => '443',
    docroot                   => false,
    manage_docroot            => false,
    access_log                => false,
    error_log                 => false,
    proxy_dest                => 'https://127.0.0.1:8000',
    proxy_preserve_host       => true,
    rewrites                  => [
      {
        rewrite_cond => ['%{HTTP:Connection} Upgrade [NC]', '%{HTTP:Upgrade} websocket [NC]'],
        rewrite_rule => ['/(.*) wss://127.0.0.1:8000/$1 [P,L]'],
      },
    ],
    ssl                       => true,
    ssl_cert                  => "/etc/letsencrypt/live/${domain_name}/fullchain.pem",
    ssl_key                   => "/etc/letsencrypt/live/${domain_name}/privkey.pem",
    ssl_proxyengine           => true,
    ssl_proxy_check_peer_cn   => 'off',
    ssl_proxy_check_peer_name => 'off',
    headers                   => ['always set Strict-Transport-Security "max-age=15768000"']
  }

  $ipa_server_ip = lookup('profile::freeipa::client::server_ip')
  $portal_port = lookup('profile::freeipa::mokey::port')

  apache::vhost { 'my80_to_my443':
    servername      => "portal.${domain_name}",
    port            => '80',
    redirect_status => 'permanent',
    redirect_dest   => "https://my.${domain_name}/",
    docroot         => false,
    manage_docroot  => false,
    access_log      => false,
    error_log       => false,
  }

  apache::vhost { 'my_ssl':
    servername                => "my.${domain_name}",
    port                      => '443',
    docroot                   => false,
    manage_docroot            => false,
    access_log                => false,
    error_log                 => false,
    proxy_dest                => "http://${ipa_server_ip}:${portal_port}",
    proxy_preserve_host       => true,
    ssl                       => true,
    ssl_cert                  => "/etc/letsencrypt/live/${domain_name}/fullchain.pem",
    ssl_key                   => "/etc/letsencrypt/live/${domain_name}/privkey.pem",
    ssl_proxyengine           => true,
    ssl_proxy_check_peer_cn   => 'off',
    ssl_proxy_check_peer_name => 'off',
    headers                   => ['always set Strict-Transport-Security "max-age=15768000"']
  }

  apache::vhost { 'ipa80_to_ipa443':
    servername      => "ipa.${domain_name}",
    port            => '80',
    redirect_status => 'permanent',
    redirect_dest   => "https://ipa.${domain_name}/",
    docroot         => false,
    manage_docroot  => false,
    access_log      => false,
    error_log       => false,
  }

  apache::vhost { 'ipa_ssl':
    servername                => "ipa.${domain_name}",
    port                      => '443',
    docroot                   => false,
    manage_docroot            => false,
    access_log                => false,
    error_log                 => false,
    proxy_preserve_host       => true,
    rewrites                  => [
      {
        rewrite_cond => ['%{HTTPS:Connection} Upgrade [NC]'],
      },
    ],
    ssl                       => true,
    ssl_cert                  => "/etc/letsencrypt/live/${domain_name}/fullchain.pem",
    ssl_key                   => "/etc/letsencrypt/live/${domain_name}/privkey.pem",
    ssl_proxyengine           => true,
    ssl_proxy_check_peer_cn   => 'off',
    ssl_proxy_check_peer_name => 'off',
    headers                   => ['always set Strict-Transport-Security "max-age=15768000"'],
    proxy_pass                => [
      {
        'path'            => '/',
        'url'             => "https://ipa.int.${domain_name}/",
        'reverse_cookies' => [
          {
            'domain' => "ipa.int.${domain_name}",
            'url'    => "ipa.${domain_name}"
          },
        ],
      }
    ],

  }
}
