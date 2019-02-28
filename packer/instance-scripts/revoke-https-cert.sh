#!/bin/bash
set -u -o pipefail

function clear_ssl_certs {
    sudo certbot revoke --delete-after-revoke --reason superseded --cert-path /etc/letsencrypt/archive/guardian/cert1.pem
}

clear_ssl_certs