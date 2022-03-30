class profile::reverse_proxy(
  String $domain_name,
  String $jupyterhub_subdomain,
  String $ipa_subdomain,
  String $mokey_subdomain,
  )
{
  selinux::boolean { 'httpd_can_network_connect': }

  class { 'apache':
    default_vhost => false,
    servername    => $domain_name,
  }

  include apache::mod::proxy_wstunnel

  firewall { '200 httpd public':
    chain  => 'INPUT',
    dport  => [80, 443],
    proto  => 'tcp',
    source => '0.0.0.0/0',
    action => 'accept'
  }

  if $domain_name in $::facts['letsencrypt'] {
    $chain_exists = $::facts['letsencrypt'][$domain_name]['chain']
    $privkey_exists = $::facts['letsencrypt'][$domain_name]['privkey']
    $fullchain_exists = $::facts['letsencrypt'][$domain_name]['fullchain']
    $willexpire = $::facts['letsencrypt'][$domain_name]['willexpire']
  } else {
    $chain_exists = false
    $privkey_exists = false
    $fullchain_exists = false
    $willexpire = false
  }

  if $chain_exists and $privkey_exists and $fullchain_exists {
    if !$willexpire {
      class { 'profile::reverse_proxy::ssl':
        domain_name          => $domain_name,
        jupyterhub_subdomain => $jupyterhub_subdomain,
        ipa_subdomain        => $ipa_subdomain,
        mokey_subdomain      =>  $mokey_subdomain
      }
    } else {
      notify { ' profile::reverse_proxy::ssl expired':
        message => "WARNING: ${domain_name} SSL certificate will expire or is expired. Renew it."
      }
    }
  } else {
    notify { ' profile::reverse_proxy::ssl expired':
      message => "WARNING: No SSL certificate for ${domain_name} was found. Apache vhosts are deactivated."
    }
  }
}

class profile::reverse_proxy::ssl(
  String $domain_name,
  String $jupyterhub_subdomain,
  String $ipa_subdomain,
  String $mokey_subdomain,
) {

  class { 'apache::mod::ssl':
    ssl_compression      => false,
    ssl_cipher           => 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384',
    ssl_protocol         => ['all', '-SSLv3', '-TLSv1', '-TLSv1.1'],
    ssl_honorcipherorder => false,
    ssl_ca               => "/etc/letsencrypt/live/${domain_name}/chain.pem",
  }

  apache::vhost { 'domain_to_jupyter_non_ssl':
    servername      => $domain_name,
    port            => '80',
    redirect_status => 'permanent',
    redirect_dest   => "https://${jupyterhub_subdomain}.${domain_name}/",
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
    redirect_dest   => "https://${jupyterhub_subdomain}.${domain_name}/",
    docroot         => false,
    manage_docroot  => false,
    access_log      => false,
    error_log       => false,
    ssl             => true,
    ssl_cert        => "/etc/letsencrypt/live/${domain_name}/fullchain.pem",
    ssl_key         => "/etc/letsencrypt/live/${domain_name}/privkey.pem",
    priority        => 99,
  }

  apache::vhost { 'jupyterhub80_to_jupyterhub443':
    servername      => "${jupyterhub_subdomain}.${domain_name}",
    port            => '80',
    redirect_status => 'permanent',
    redirect_dest   => "https://${jupyterhub_subdomain}.${domain_name}/",
    docroot         => false,
    manage_docroot  => false,
    access_log      => false,
    error_log       => false,
  }

  $jupyterhub_bind_host_port = join(split($jupyterhub::bind_url, /:/)[1,-1], ':')
  apache::vhost { 'jupyterhub_ssl':
    servername                => "${jupyterhub_subdomain}.${domain_name}",
    port                      => '443',
    docroot                   => false,
    manage_docroot            => false,
    access_log                => false,
    error_log                 => false,
    proxy_dest                => $jupyterhub::bind_url,
    proxy_preserve_host       => true,
    rewrites                  => [
      {
        rewrite_cond => ['%{HTTP:Connection} Upgrade [NC]', '%{HTTP:Upgrade} websocket [NC]'],
        rewrite_rule => ["/(.*) wss:${jupyterhub_bind_host_port}/\$1 [P,L]"],
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
  $mokey_port = lookup('profile::freeipa::mokey::port')

  apache::vhost { 'mokey80_to_mokey443':
    servername      => "${mokey_subdomain}.${domain_name}",
    port            => '80',
    redirect_status => 'permanent',
    redirect_dest   => "https://${mokey_subdomain}.${domain_name}/",
    docroot         => false,
    manage_docroot  => false,
    access_log      => false,
    error_log       => false,
  }

  apache::vhost { 'mokey_ssl':
    servername                => "${mokey_subdomain}.${domain_name}",
    port                      => '443',
    docroot                   => false,
    manage_docroot            => false,
    access_log                => false,
    error_log                 => false,
    proxy_dest                => "http://${ipa_server_ip}:${mokey_port}",
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
    servername      => "${ipa_subdomain}.${domain_name}",
    port            => '80',
    redirect_status => 'permanent',
    redirect_dest   => "https://${ipa_subdomain}.${domain_name}/",
    docroot         => false,
    manage_docroot  => false,
    access_log      => false,
    error_log       => false,
  }

  apache::vhost { 'ipa_ssl':
    servername                => "${ipa_subdomain}.${domain_name}",
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
        'url'             => "https://${ipa_subdomain}.int.${domain_name}/",
        'reverse_cookies' => [
          {
            'domain' => "${ipa_subdomain}.int.${domain_name}",
            'url'    => "${ipa_subdomain}.${domain_name}"
          },
        ],
      }
    ],

  }
}
