#!/bin/bash
set -u -o pipefail

function clear_ssl_certs {
    local readonly ENABLE_HTTPS=$(cat /opt/guardian/info/enable-https.txt)
    if [ "$ENABLE_HTTPS" == "true" ]
    then
        sudo certbot revoke --delete-after-revoke --reason superseded --cert-path /etc/letsencrypt/archive/guardian/cert1.pem
    fi
}

clear_ssl_certs