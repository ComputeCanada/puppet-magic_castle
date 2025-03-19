class profile::puppetserver {
  $local_users = lookup('profile::users::local::users', undef, undef, {})
  $local_users.each | $user, $attrs | {
    if pick($attrs['sudoer'], false) {
      file_line { "${user}_eyamlbootstrap":
        path => "/${user}/.bashrc",
        line => 'alias eyamlbootstrap="sudo /opt/puppetlabs/puppet/bin/eyaml decrypt --pkcs7-private-key /etc/puppetlabs/puppet/eyaml/boot_private_key.pkcs7.pem -f /etc/puppetlabs/code/environments/production/data/bootstrap.yaml | less"'
      }
    }
  }
}
