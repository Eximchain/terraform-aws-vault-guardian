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

function download_certs_from_s3 {
    aws configure set s3.signature_version s3v4
    aws s3 cp s3://${vault_cert_bucket}/ca.crt.selfsigned.pem $VAULT_TLS_CERT_DIR
    aws s3 cp s3://${vault_cert_bucket}/vault.crt.selfsigned.pem $VAULT_TLS_CERT_DIR
    aws s3 cp s3://${vault_cert_bucket}/vault.key.selfsigned.pem $VAULT_TLS_CERT_DIR

    aws s3 cp s3://${vault_cert_bucket}/chain.pem $VAULT_TLS_CERT_DIR
    aws s3 cp s3://${vault_cert_bucket}/cert.pem $VAULT_TLS_CERT_DIR
    aws s3 cp s3://${vault_cert_bucket}/privkey.pem $VAULT_TLS_CERT_DIR
    cat $VAULT_TLS_CERT_DIR/cert.pem $VAULT_TLS_CERT_DIR/chain.pem | sudo tee $VAULT_TLS_CERT_DIR/fullchain.pem > /dev/null 2>&1
}

function configure_local_vault_dns {
    local readonly HOSTS_FILE="/etc/hosts"
    local readonly HOSTNAME=$(cat /opt/vault/custom-domain.txt)

    echo "" | sudo tee -a $HOSTS_FILE > /dev/null 2>&1
    echo "127.0.0.1 $HOSTNAME" | sudo tee -a $HOSTS_FILE > /dev/null 2>&1
}

readonly PLUGIN_DIR="/opt/vault/bin/plugins"

populate_data_files
configure_local_vault_dns

/opt/vault/bin/generate-setup-vault.sh

download_certs_from_s3

# Set ownership and permissions
sudo chown vault:vault $VAULT_TLS_CERT_DIR/*
sudo chmod 600 $VAULT_TLS_CERT_DIR/*
sudo /opt/vault/bin/update-certificate-store --cert-file-path $VAULT_TLS_SELFSIGNED_CA

/opt/consul/bin/run-consul --server --cluster-tag-key "${consul_cluster_tag_key}" --cluster-tag-value "${consul_cluster_tag_value}"
/opt/vault/bin/run-vault --s3-bucket "${s3_bucket_name}" --s3-bucket-region "${aws_region}"  --api-addr "${vault_api_addr}" --log-level "${vault_log_level}" --tls-cert-file "$VAULT_TLS_CERT_FILE"  --tls-key-file "$VAULT_TLS_KEY_FILE" --plugin-dir "$PLUGIN_DIR"