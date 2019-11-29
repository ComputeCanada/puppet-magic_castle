class profile::reverse_proxy(String $domain_name)
{
  selinux::boolean { 'httpd_can_network_connect': }

  class { 'apache':
    default_vhost => false,
  }

  class { 'apache::mod::ssl':
    ssl_compression      => false,
    ssl_cert             => "/etc/letsencrypt/live/${domain_name}/fullchain.pem",
    ssl_key              => "/etc/letsencrypt/live/${domain_name}/privkey.pem",
    ssl_ca               => "/etc/letsencrypt/live/${domain_name}/chain.pem",
    ssl_cipher           => 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384',
    ssl_protocol         => [' all', '-SSLv3', '-TLSv1', '-TLSv1.1'],
    ssl_honorcipherorder => false,
  }

  apache::mod { ['proxy', 'proxy_http']: }

  firewall { '200 nginx public':
    chain  => 'INPUT',
    dport  => [80, 443],
    proto  => 'tcp',
    source => '0.0.0.0/0',
    action => 'accept'
  }

  # service { 'httpd':
  #   ensure => running,
  #   enable => true
  # }

  # file_line { 'SSLCertificateFile':
  #   ensure => present,
  #   path   => '/etc/httpd/conf.d/ssl.conf',
  #   line   => "SSLCertificateFile /etc/letsencrypt/live/${domain_name}/fullchain.pem",
  #   notify => Service['httpd']
  # }

  # file_line { 'SSLCertificateKeyFile':
  #   ensure => present,
  #   path   => '/etc/httpd/conf.d/ssl.conf',
  #   line   => "SSLCertificateKeyFile /etc/letsencrypt/live/${domain_name}/privkey.pem",
  #   notify => Service['httpd']
  # }

  # file_line { 'SSLCACertificateFile':
  #   ensure => present,
  #   path   => '/etc/httpd/conf.d/ssl.conf',
  #   line   => "SSLCACertificateFile /etc/letsencrypt/live/${domain_name}/chain.pem",
  #   notify => Service['httpd']
  # }

  # file_line { 'SSLProtocol':
  #   ensure => present,
  #   path   => '/etc/httpd/conf.d/ssl.conf',
  #   line   => 'SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1',
  #   notify => Service['httpd']
  # }

  # file_line { 'SSLCipherSuite':
  #   ensure => present,
  #   path   => '/etc/httpd/conf.d/ssl.conf',
  #   line   => 'SSLCipherSuite ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384',
  #   notify => Service['httpd']
  # }

  # file_line { 'SSLHonorCipherOrder':
  #   ensure => present,
  #   path   => '/etc/httpd/conf.d/ssl.conf',
  #   line   => 'SSLHonorCipherOrder off',
  #   notify => Service['httpd']
  # }

  # file_line { 'Strict-Transport-Security':
  #   ensure => present,
  #   path   => '/etc/httpd/conf.d/ssl.conf',
  #   line   => 'Header always set Strict-Transport-Security "max-age=15768000"',
  #   notify => Service['httpd']
  # }
}

# class profile::reverse_proxy::jupyterhub
# jupyterhub.conf
# <VirtualHost *:80>
#   ServerName mando.calculquebec.cloud
#   Redirect / https://jupyter.mando.calculquebec.cloud/
# </VirtualHost>

# <VirtualHost *:443>
#   SSLEngine on
#   ServerName mando.calculquebec.cloud
#   Redirect / https://jupyter.mando.calculquebec.cloud/
# </VirtualHost>

# <VirtualHost *:80>
#   ServerName jupyter.mando.calculquebec.cloud
#   Redirect / https://jupyter.mando.calculquebec.cloud/
# </VirtualHost>
# <VirtualHost *:443>
#   ServerName jupyter.mando.calculquebec.cloud

#   # configure SSL
#   SSLEngine on
#   SSLProxyEngine on

#   SSLProxyCheckPeerCN off
#   SSLProxyCheckPeerName off

#   # Use RewriteEngine to handle websocket connection upgrades
#   RewriteEngine On
#   RewriteCond %{HTTPS:Connection} Upgrade [NC]
#   RewriteCond %{HTTPS:Upgrade} websocket [NC]
#   RewriteRule /(.*) wss://127.0.0.1:8000/$1 [P,L]

#   <Location "/">
#     # preserve Host header to avoid cross-origin problems
#     ProxyPreserveHost on
#     # proxy to JupyterHub
#     ProxyPass         https://127.0.0.1:8000/
#     ProxyPassReverse  https://127.0.0.1:8000/
#   </Location>
# </VirtualHost>


# login1:ipa.conf
# <VirtualHost *:443>
#   ServerName login1.mando.calculquebec.cloud

#   # configure SSL
#   SSLEngine on
#   SSLProxyEngine on

#   SSLProxyCheckPeerCN off
#   SSLProxyCheckPeerName off

#   # Use RewriteEngine to handle websocket connection upgrades
#   RewriteEngine On
#   RewriteCond %{HTTPS:Connection} Upgrade [NC]

#   ProxyPassReverseCookieDomain mgmt1.int.mando.calculquebec.cloud login1.mando.calculquebec.cloud
#   RequestHeader edit Referer ^https://login1\.mando\.calculquebec\.cloud/ https://mgmt1.int.mando.calculquebec.cloud/

#   <Location "/">
#     # preserve Host header to avoid cross-origin problems
#     ProxyPreserveHost on
#     # proxy to FreeIPA
#     ProxyPass         https://mgmt1.int.mando.calculquebec.cloud/
#     ProxyPassReverse  https://mgmt1.int.mando.calculquebec.cloud/
#   </Location>
# </VirtualHost>
# mgmt1:/etc/httpd/conf.d/ipa-rewrite.conf
# # VERSION 6 - DO NOT REMOVE THIS LINE

# RewriteEngine on

# # By default forward all requests to /ipa. If you don't want IPA
# # to be the default on your web server comment this line out.
# RewriteRule ^/$ /ipa/ui [L,NC,R=301]

# # Redirect to the fully-qualified hostname. Not redirecting to secure
# # port so configuration files can be retrieved without requiring SSL.
# #RewriteCond %{HTTP_HOST}    !^mgmt1.int.mando.calculquebec.cloud$ [NC]
# #RewriteRule ^/ipa/(.*)      http://mgmt1.int.mando.calculquebec.cloud/ipa/$1 [L,R=301]

# # Redirect to the secure port if not displaying an error or retrieving
# # configuration.
# #RewriteCond %{SERVER_PORT}  !^443$
# #RewriteCond %{REQUEST_URI}  !^/ipa/(errors|config|crl)
# #RewriteCond %{REQUEST_URI}  !^/ipa/[^\?]+(\.js|\.css|\.png|\.gif|\.ico|\.woff|\.svg|\.ttf|\.eot)$
# #RewriteRule ^/ipa/(.*)      https://mgmt1.int.mando.calculquebec.cloud/ipa/$1 [L,R=301,NC]

# # Rewrite for plugin index, make it like it's a static file
# RewriteRule ^/ipa/ui/js/freeipa/plugins.js$    /ipa/wsgi/plugins.py [PT]
