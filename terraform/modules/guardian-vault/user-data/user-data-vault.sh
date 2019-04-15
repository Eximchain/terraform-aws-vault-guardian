#!/bin/bash
# This script is meant to be run in the User Data of each EC2 Instance while it's booting. The script uses the
# run-consul script to configure and start Consul in client mode and then the run-vault script to configure and start
# Vault in server mode. Note that this script assumes it's running in an AMI built from the Packer template in
# examples/vault-consul-ami/vault-consul.json.

set -e

# Send the log output from this script to user-data.log, syslog, and the console
# From: https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

readonly VAULT_TLS_CERT_DIR="/opt/vault/tls"

readonly VAULT_TLS_SELFSIGNED_CA="$VAULT_TLS_CERT_DIR/ca.crt.selfsigned.pem"

readonly VAULT_TLS_CERT_FILE="$VAULT_TLS_CERT_DIR/fullchain.pem"
readonly VAULT_TLS_KEY_FILE="$VAULT_TLS_CERT_DIR/privkey.pem"
readonly VAULT_TLS_SINGLE_CERT_FILE="$VAULT_TLS_CERT_DIR/cert.pem"

function populate_data_files {
    echo "${okta_api_token}" | sudo tee /opt/vault/okta-api-token.txt > /dev/null 2>&1
    echo "${vault_api_addr}" | sudo tee /opt/vault/custom-domain.txt > /dev/null 2>&1
}

# TODO: Get this working
function get_ssl_certs_http {
    # TODO: Don't start the nginx server in the first place
    sudo nginx -s stop
    # LetsEncrypt requires a webmaster email in case of issues.  Must specify custom domain
    # we want certs for.  Note that we only use custom b/c they don't give certs to .amazonaws.com
    # domains.  Including the --cert-name option ensures that we know what directory the keys
    # are placed in, and it tells LetsEncrypt which nginx config to update.
    local readonly CERT_WEBMASTER="louis@eximchain.com"
    local readonly DOMAIN=$(cat /opt/vault/custom-domain.txt)
    sudo certbot certonly --cert-name guardian --standalone --noninteractive --agree-tos -m $CERT_WEBMASTER -d $DOMAIN
}

function get_ssl_certs_dns {
  # LetsEncrypt requires a webmaster email in case of issues.  Must specify custom domain
  # we want certs for.  Note that we only use custom b/c they don't give certs to .amazonaws.com
  # domains.  Including the --cert-name option ensures that we know what directory the keys
  # are placed in, and it tells LetsEncrypt which nginx config to update.
  local readonly CERT_WEBMASTER="louis@eximchain.com"
  local readonly DOMAIN=$(cat /opt/vault/custom-domain.txt)
  sudo certbot certonly --cert-name guardian --dns-route53 --noninteractive --agree-tos -m $CERT_WEBMASTER -d $DOMAIN
}

function download_selfsigned_certs_from_s3 {
    aws configure set s3.signature_version s3v4
    aws s3 cp s3://${vault_cert_bucket}/ca.crt.selfsigned.pem $VAULT_TLS_CERT_DIR
    aws s3 cp s3://${vault_cert_bucket}/vault.crt.selfsigned.pem $VAULT_TLS_CERT_DIR
    aws s3 cp s3://${vault_cert_bucket}/vault.key.selfsigned.pem $VAULT_TLS_CERT_DIR
}

function copy_certbot_certs {
    local readonly CERTBOT_CERT_DIR="/etc/letsencrypt/live/guardian"
    local readonly VAULT_CERTBOT_CERT_FILE="$CERTBOT_CERT_DIR/fullchain.pem"
    local readonly VAULT_CERTBOT_KEY_FILE="$CERTBOT_CERT_DIR/privkey.pem"
    local readonly VAULT_CERTBOT_SINGLE_CERT_FILE="$CERTBOT_CERT_DIR/cert.pem"
    local readonly VAULT_CERTBOT_CA_FILE="$CERTBOT_CERT_DIR/chain.pem"

    sudo cp $VAULT_CERTBOT_CERT_FILE $VAULT_TLS_CERT_DIR
    sudo cp $VAULT_CERTBOT_KEY_FILE $VAULT_TLS_CERT_DIR
    sudo cp $VAULT_CERTBOT_CA_FILE $VAULT_TLS_CERT_DIR
    sudo cp $VAULT_CERTBOT_SINGLE_CERT_FILE $VAULT_TLS_CERT_DIR
}

readonly PLUGIN_DIR="/opt/vault/bin/plugins"

populate_data_files

/opt/vault/bin/generate-setup-vault.sh

# Self-signed certs for local interface
download_selfsigned_certs_from_s3

# Let's Encrypt certs for internet interface
get_ssl_certs_dns
copy_certbot_certs

# Set ownership and permissions
sudo chown vault:vault $VAULT_TLS_CERT_DIR/*
sudo chmod 600 $VAULT_TLS_CERT_DIR/*
sudo /opt/vault/bin/update-certificate-store --cert-file-path $VAULT_TLS_SELFSIGNED_CA

/opt/consul/bin/run-consul --server --cluster-tag-key "${consul_cluster_tag_key}" --cluster-tag-value "${consul_cluster_tag_value}"
/opt/vault/bin/run-vault --s3-bucket "${s3_bucket_name}" --s3-bucket-region "${aws_region}"  --api-addr "${vault_api_addr}" --log-level "${vault_log_level}" --tls-cert-file "$VAULT_TLS_CERT_FILE"  --tls-key-file "$VAULT_TLS_KEY_FILE" --plugin-dir "$PLUGIN_DIR"