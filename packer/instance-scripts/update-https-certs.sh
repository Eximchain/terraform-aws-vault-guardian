#!/bin/bash
set -eu -o pipefail

function assert_sudo {
    if [ $EUID -ne 0 ]
    then 
        echo "This script requires root access. Please try again using 'sudo'"
        exit
    fi
}

function download_certs_from_s3 {
    local readonly VAULT_TLS_CERT_DIR="/opt/vault/tls"

    local readonly CERT_BUCKET=$(cat /opt/vault/cert-bucket.txt)

    aws configure set s3.signature_version s3v4
    aws s3 cp s3://$CERT_BUCKET/ca.crt.selfsigned.pem $VAULT_TLS_CERT_DIR
    aws s3 cp s3://$CERT_BUCKET/vault.crt.selfsigned.pem $VAULT_TLS_CERT_DIR
    aws s3 cp s3://$CERT_BUCKET/vault.key.selfsigned.pem $VAULT_TLS_CERT_DIR

    aws s3 cp s3://$CERT_BUCKET/chain.pem $VAULT_TLS_CERT_DIR
    aws s3 cp s3://$CERT_BUCKET/cert.pem $VAULT_TLS_CERT_DIR
    aws s3 cp s3://$CERT_BUCKET/privkey.pem $VAULT_TLS_CERT_DIR
    cat $VAULT_TLS_CERT_DIR/cert.pem $VAULT_TLS_CERT_DIR/chain.pem | sudo tee $VAULT_TLS_CERT_DIR/fullchain.pem > /dev/null 2>&1
}

function reload_vault_certs {
    pkill --uid vault --signal SIGHUP
    echo "Successfully sent SIGHUP signal to vault to refresh certificates"
}

assert_sudo
download_certs_from_s3
reload_vault_certs