#!/bin/bash

puppet_server=$(incus list --columns "nd" -f csv | grep \"puppet\" | cut -d',' -f1)

for nodename in $(incus list -c n -f csv); do
    incus file pull $puppet_server/var/lib/node_exporter/puppet_report_${nodename}.prom .
    incus exec $nodename -- journalctl -u puppet -o json > journalctl-puppet-${nodename}.json
done