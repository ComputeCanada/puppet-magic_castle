#!/bin/sh
echo "---"
echo '"ipa":'
echo '  "installed":' $(test -f /etc/ipa/default.conf && echo "true" || echo "false")
echo '  "domain":' $(test -f /etc/ipa/default.conf && grep -oP 'domain\s*=\s*\K(.*)' /etc/ipa/default.conf)
