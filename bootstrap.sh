#!/bin/sh
# Check if the puppet module for consul is present
# If it is, initialize the consul server
if [ -d /etc/puppetlabs/code/environments/production/modules/consul ]; then
    /opt/puppetlabs/bin/puppet apply -e 'include profile::consul::server'
fi
