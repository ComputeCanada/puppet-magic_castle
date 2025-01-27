# Configuring multifactor authentication with Duo Unix
## Adding `duo_unix` to your `Puppetfile` 
In order to support multifactor authentication with Duo, you will first need to add the `duo_unix` Puppet module to your `Puppetfile` 
and define it in your [`main.tf`](https://github.com/ComputeCanada/magic_castle/tree/main/docs#419-puppetfile-optional). If you want to 
use the original version, you would add
```
mod 'iu-duo_unix', '4.0.1'
``` 
to your `Puppetfile`. 

## Adding `duo_unix` to your instances
You need to add the `duo_unix` module to your instances using Magic Castle [tags](https://github.com/ComputeCanada/puppet-magic_castle/tree/main?tab=readme-ov-file#magic_castlesite). 
To do so,  define a new tag, and apply it to your instances through the `main.tf`: 
```
magic_castle::site::tags:
  worldssh:
    - duo_unix
```
and then in your `main.tf`, add the `worldssh` tag to your `login` instance: 
```
    login  = { type = "...", tags = ["login", "public", "worldssh"], count = 1 }
```

## Adding your Duo configuration
In your hieradata file, add the following: 
```
duo_unix::usage: 'pam'
duo_unix::ikey: <your ikey>
duo_unix::skey: <your skey>
duo_unix::host: <your duo host>
duo_unix::motd: 'yes'
duo_unix::groups: '*,!centos'
duo_unix::pam_ssh_config::keyonly: true  # optional
``` 
where the last line is if you want to restrict the primary authentication to SSH keys only. Since this configuration contains
secrets, it is strongly recommended generate and upload [eyaml certificates](https://github.com/ComputeCanada/magic_castle/tree/main/docs#1013-generate-and-replace-puppet-hieradata-encryption-keys)
and use them to [encrypt your data](https://simp.readthedocs.io/en/master/HOWTO/20_Puppet/Hiera_eyaml.html).

# Configuring `sudo`
## Adding `saz-sudo` to your `Puppetfile` 
If you want to configure `sudo` commands on your cluster, you will want to add the [`saz-sudo`](https://forge.puppet.com/modules/saz/sudo/readme) Puppet module to your `Puppetfile` 
and define it in your [`main.tf`](https://github.com/ComputeCanada/magic_castle/tree/main/docs#419-puppetfile-optional). You would add
```
mod 'saz-sudo', '8.0.0'
``` 
to your `Puppetfile`. 

## Adding `sudo` to your instances
You need to add the `sudo` module to your instances using Magic Castle [tags](https://github.com/ComputeCanada/puppet-magic_castle/tree/main?tab=readme-ov-file#magic_castlesite). 
To do so, define a new tag and apply it to your instances through the `main.tf`: 
```
magic_castle::site::tags:
  sudo:
    - sudo
```
and then in your `main.tf`, add the `sudo` tag to your instance: 
```
    login  = { type = "...", tags = ["login", "public", "sudo"], count = 1 }
```

## Adding your `sudo` configuration
Add the content of `sudoers` files to your hieradata. For example: 
```
sudo::ldap_enable: true
sudo::config_file_replace: false
sudo::prefix: '10-mysudoers_'
sudo::purge_ignore: '[!10-mysudoers_]*'
sudo::configs:
  'general':
    'content': |
      Cmnd_Alias ADMIN_ROOTCMD = /bin/cat *, /bin/ls *, /bin/chmod *, /bin/vim *, /usr/bin/su -, /bin/yum *, /bin/less *, /bin/grep *, /bin/kill *, /usr/sbin/reboot
      %admin ALL=(ALL)      NOPASSWD: ADMIN_ROOTCMD
```

# Configuring a system's `cron` 
## Adding `puppet-cron` to your `Puppetfile` 
If you want to configure `cron` commands on your cluster, you will want to add the [`puppet-cron`]([https://forge.puppet.com/modules/saz/sudo/readme](https://github.com/voxpupuli/puppet-cron)) Puppet module to your `Puppetfile` 
and define it in your [`main.tf`](https://github.com/ComputeCanada/magic_castle/tree/main/docs#419-puppetfile-optional). You would add
```
mod 'puppet-cron', '2.0.0'
``` 
to your `Puppetfile`. 

## Adding `cron` to your instances
You need to add the `cron` module to your instances using Magic Castle [tags](https://github.com/ComputeCanada/puppet-magic_castle/tree/main?tab=readme-ov-file#magic_castlesite). 
Define a new tag, and apply it to your instances through the `main.tf`: 
```
magic_castle::site::tags:
  cron:
    - cron
```
and then in your `main.tf`, add the `sudo` tag to your instance: 
```
    login  = { type = "...", tags = ["login", "public", "cron"], count = 1 }
```

## Adding your `cron` configuration
Add the configuration to your hieradata. For example: 
```
cron::job:
  mii_cache:
    command: 'source $HOME/.bashrc; /etc/rsnt/generate_mii_index.py --arch sse3 avx avx2 avx512 &>> /home/ebuser/crontab_mii.log'
    minute: '*/10'
    hour: '*'
    date: '*'
    month: '*'
    weekday: '*'
    user: ebuser
    description: 'Generate Mii cache'
``` 

# Creating a HAProxy instance
If you are using external LDAP replicas instead of the local FreeIPA, you may wish to configure an instance to run a (HAProxy)[https://www.haproxy.org/]
load balancer. This can be useful for example if you want to route all queries to LDAP through a single instance, so that the LDAPs' firewalls only need
to be opened for a single IP address. 

## Adding `puppetlabs-haproxy` to your `Puppetfile` 
If you want to configure a HAProxy instance in your cluster, you will want to add the [`puppetlabs-haproxy`](https://forge.puppet.com/modules/puppetlabs/haproxy/readme) Puppet module to your `Puppetfile` 
and define it in your [`main.tf`](https://github.com/ComputeCanada/magic_castle/tree/main/docs#419-puppetfile-optional). You would add
```
mod 'puppetlabs-haproxy', '8.0.0'
``` 
to your `Puppetfile`. 

## Adding a HAProxy instance
You need to add an instance with the `haproxy` module. Create a new tag, and apply it to your instances through the `main.tf`: 
```
magic_castle::site::tags:
  haproxy:
    - haproxy
```
and then in your `main.tf`, add the `sudo` tag to your instance: 
```
    haproxy  = { type = "p2-3gb", tags = ["haproxy"], count = 1 }
```

## Configuring your HAproxy instance
Add the HAProxy configuration to your hieradata, for example: 
```
haproxy::merge_options: false
haproxy::defaults_options:
  log: global
  option: ['tcplog', 'tcpka']
  balance: first
  timeout server: 1800s
  timeout connect: 2s
  mode: tcp

haproxy::custom_fragment: |

  frontend ldaps_service_front
    mode                  tcp
    bind                  %{lookup('terraform.self.local_ip')}:636
    description           LDAPS Service
    option                socket-stats
    option                tcpka
    timeout client        3600s
    default_backend       ldaps_service_back

  backend ldaps_service_back
    server                ldap-1 <server1>:636 check fall 1 rise 1 inter 2s
    server                ldap-2 <server1>:636 check fall 1 rise 1 inter 2s
    option                ssl-hello-chk
```


## Configuring your other instances to query the HAProxy
For a LDAP HAProxy, you will then want to configure your other instances to use that proxy as LDAP source: 
```
profile::sssd::client::domains:
  MYLDAP:
    id_provider: ldap
    auth_provider: ldap
    ldap_schema: rfc2307
    ldap_uri:
      - ldaps://haproxy1
    .....
```
