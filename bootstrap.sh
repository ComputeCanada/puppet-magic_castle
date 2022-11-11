#!/bin/sh
# Initialize random hieradata values
set -e
PATH=$PATH:/opt/puppetlabs/puppet/bin
(
    eyaml encrypt -l 'profile::consul::acl_api_token' -o block -s $(uuidgen) --pkcs7-public-key=/etc/puppetlabs/puppet/eyaml/boot_public_key.pkcs7.pem
    eyaml encrypt -l 'profile::slurm::base::munge_key' -o block -s $(openssl rand 1024 | openssl enc -A -base64) --pkcs7-public-key=/etc/puppetlabs/puppet/eyaml/boot_public_key.pkcs7.pem
    eyaml encrypt -l 'profile::slurm::accounting::password' -o block -s $(openssl rand -base64 9) --pkcs7-public-key=/etc/puppetlabs/puppet/eyaml/boot_public_key.pkcs7.pem
    eyaml encrypt -l 'profile::freeipa::mokey::password' -o block -s $(openssl rand -base64 9) --pkcs7-public-key=/etc/puppetlabs/puppet/eyaml/boot_public_key.pkcs7.pem
) >> /etc/puppetlabs/code/environments/production/data/bootstrap.yaml

# Check if the puppet module for consul is present
# If it is, initialize the consul server
if [ -d /etc/puppetlabs/code/environments/production/modules/consul ]; then
    /opt/puppetlabs/bin/puppet apply -e 'include profile::consul::server'
fi
