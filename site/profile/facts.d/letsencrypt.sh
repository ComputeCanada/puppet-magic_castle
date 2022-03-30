#!/bin/sh

echo "---"
echo "letsencrypt:"
for path in /etc/letsencrypt/live/*; do
    domain=$(basename $path)
    echo "  $domain:"
    echo "    fullchain: " $(test -e $path/fullchain.pem && echo true || echo false)
    echo "    cert: " $(test -e $path/cert.pem && echo true || echo false)
    echo "    privkey: " $(test -e $path/privkey.pem && echo true || echo false)
    echo "    chain: " $(test -e $path/chain.pem && echo true || echo false)
    echo "    startdate: " $(openssl x509 -in $path/fullchain.pem -startdate | cut -d= -f2)
    echo "    enddate: " $(openssl x509 -in $path/fullchain.pem -enddate | cut -d= -f2)
done