#!/bin/bash
INPUT=$(cat -)
logger ${INPUT}

# No event, dry run of handler
if [[ "${INPUT}" == "[]" ]]; then
  exit 0;
fi

event_type=$(echo $INPUT | jq -r '.[-1] | .Name')

if [[ "$event_type" != "puppet" ]]; then
  exit 0
fi

payload=$(echo $INPUT | jq -r '.[-1] | .Payload' | base64 -d)

if [ -f /opt/puppetlabs/puppet/cache/state/agent_catalog_run.lock ]; then
  # Puppet is already running, we check if the event precedes the start of the current run
  # If it is, we ignore it, otherwise we wait for the run to complete and then we restart
  puppet_begin=$(stat -c %W /opt/puppetlabs/puppet/cache/state/agent_catalog_run.lock)
  if [ "${puppet_begin}" -gt "${payload}" ]; then
    exit 0
  fi
  while [ -f /opt/puppetlabs/puppet/cache/state/agent_catalog_run.lock ]; do sleep 30; done

elif [ -f /opt/puppetlabs/puppet/cache/state/last_run_summary.yaml ]; then
  # If the last puppet run began after the event timestamp, we ignore the event
  puppet_begin=$(grep '  config:' /opt/puppetlabs/puppet/cache/state/last_run_summary.yaml | cut -d: -f 2 | sed 's/ //')
  if [ "${puppet_begin}" -gt "${payload}" ]; then
    exit 0
  fi
fi

sudo systemctl reload puppet