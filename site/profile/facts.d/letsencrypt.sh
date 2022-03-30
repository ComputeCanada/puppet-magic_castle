#!/bin/sh

echo "---"
if [ -d /etc/letsencrypt ]; then
    echo "letsencrypt:"
    for domain in $(ls /etc/letsencrypt/live); do
        path=/etc/letsencrypt/live/$domain
        echo "  $domain:"
        echo "    fullchain:" $(test -e $path/fullchain.pem && echo true || echo false)
        echo "    cert:" $(test -e $path/cert.pem && echo true || echo false)
        echo "    privkey:" $(test -e $path/privkey.pem && echo true || echo false)
        echo "    chain:" $(test -e $path/chain.pem && echo true || echo false)
        if [ -e $path/fullchain.pem ]; then
            echo "    startdate:" $(openssl x509 -in $path/fullchain.pem -startdate -noout | cut -d= -f2)
            echo "    enddate:" $(openssl x509 -in $path/fullchain.pem -enddate -noout | cut -d= -f2)
            echo "    willexpire:" $(openssl x509 -in $path/fullchain.pem -checkend 1800 | grep -q "will expire" && echo true || echo false)
        fi
    done
else
    echo "letsencrypt: {}"
fi