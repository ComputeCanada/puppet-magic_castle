#!/bin/sh
set -e
PATH=$PATH:/opt/puppetlabs/puppet/bin
ENVIRONMENT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

if [ ! -e /etc/puppetlabs/data/credentials.yaml ]; then
    ${ENVIRONMENT_DIR}/generate_credentials.sh
fi

# Apply bootstrap classes if any
puppet apply ${ENVIRONMENT_DIR}/manifests/site.pp  --tags mc_bootstrap
