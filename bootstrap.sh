#!/bin/sh
# Initialize random hieradata values
set -e
PATH=$PATH:/opt/puppetlabs/puppet/bin
PKCS7_KEY="/etc/puppetlabs/puppet/eyaml/boot_public_key.pkcs7.pem"
ENC_CMD="eyaml encrypt -o block --pkcs7-public-key=${PKCS7_KEY}"
(
    $ENC_CMD -l 'jupyterhub::prometheus_token' -s $(uuidgen)
    $ENC_CMD -l 'profile::consul::acl_api_token' -s $(uuidgen)
    $ENC_CMD -l 'profile::slurm::base::munge_key' -s $(openssl rand 1024 | openssl enc -A -base64)
    $ENC_CMD -l 'profile::slurm::accounting::password' -s $(openssl rand -base64 9)
    $ENC_CMD -l 'profile::freeipa::mokey::password' -s $(openssl rand -base64 9)
    $ENC_CMD -l 'profile::freeipa::server::ds_password' -s $(openssl rand -base64 9)
    $ENC_CMD -l 'profile::freeipa::server::admin_password' -s $(openssl rand -base64 9)
) > /etc/puppetlabs/code/environments/production/data/bootstrap.yaml

# Check if the puppet module for consul is present
# If it is, initialize the consul server
if [ -d /etc/puppetlabs/code/environments/production/modules/consul ]; then
    /opt/puppetlabs/bin/puppet apply -e 'include profile::consul'
fi
