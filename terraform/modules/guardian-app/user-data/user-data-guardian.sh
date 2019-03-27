#!/bin/bash
# This script is meant to be run in the User Data of each EC2 Instance while it's booting. The script uses the
# run-consul script to configure and start Consul in server mode. Note that this script assumes it's running in an AMI
# built from the Packer template in examples/vault-consul-ami/vault-consul.json.

set -eu

readonly BASH_PROFILE_FILE="/home/ubuntu/.bash_profile"
readonly VAULT_TLS_CERT_DIR="/opt/vault/tls"
readonly CA_TLS_CERT_FILE="$VAULT_TLS_CERT_DIR/ca.crt.pem"

# This is necessary to retrieve the address for vault
echo "export VAULT_ADDR=https://${vault_dns}:${vault_port}" >> $BASH_PROFILE_FILE
source $BASH_PROFILE_FILE

sleep 60

function wait_for_successful_command {
    local COMMAND=$1

    $COMMAND
    until [ $? -eq 0 ]
    do
        sleep 5
        $COMMAND
    done
}

function write_data {
  echo "${custom_domain}" | sudo tee /opt/guardian/info/custom-domain.txt > /dev/null 2>&1
}

function write_nginx_config {
  sudo rm -rf /etc/nginx/sites-enabled/default
  local readonly HOSTNAME="$(curl http://169.254.169.254/latest/meta-data/public-hostname)"

  local readonly SERVER_NAME="${custom_domain} $HOSTNAME"

  # TODO: End-to-End TLS with Vault
  echo "
  server {
    server_name $SERVER_NAME;
    add_header 'Access-Control-Allow-Origin' '*';
    add_header 'Access-Control-Allow_Credentials' 'true';
    add_header 'Access-Control-Allow-Methods' 'GET,POST,PUT,OPTIONS';
    add_header 'Access-Control-Allow-Headers' 'Authorization,Accept,DNT,Origin,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
    add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
    location /v1/guardian/login {
      proxy_pass \"$VAULT_ADDR\";
      proxy_set_header Host \$host;
      proxy_set_header X_FORWARDED_PROTO https;
    }
    location /v1/guardian/sign {
      proxy_pass \"$VAULT_ADDR\";
      proxy_set_header Host \$host;
      proxy_set_header X_FORWARDED_PROTO https;
    }
  }" | sudo tee /etc/nginx/sites-available/guardian > /dev/null 2>&1
  sudo ln -s /etc/nginx/sites-available/guardian /etc/nginx/sites-enabled/guardian
  sudo service nginx restart
}

function get_ssl_certs {
  # LetsEncrypt requires a webmaster email in case of issues.  Must specify custom domain
  # we want certs for.  Note that we only use custom b/c they don't give certs to .amazonaws.com
  # domains.  Including the --cert-name option ensures that we know what directory the keys
  # are placed in, and it tells LetsEncrypt which nginx config to update.
  local readonly CERT_WEBMASTER="louis@eximchain.com"
  local readonly DOMAIN=$(cat /opt/guardian/info/custom-domain.txt)
  wait_for_successful_command "sudo certbot --cert-name guardian --nginx --noninteractive --agree-tos --redirect -m $CERT_WEBMASTER -d $DOMAIN"
}

function download_vault_certs {
  # Download vault certs from s3
  aws configure set s3.signature_version s3v4
  while [ -z "$(aws s3 ls s3://${vault_cert_bucket}/ca.crt.pem)" ]
  do
      echo "S3 object not found, waiting and retrying"
      sleep 5
  done
  while [ -z "$(aws s3 ls s3://${vault_cert_bucket}/vault.crt.pem)" ]
  do
      echo "S3 object not found, waiting and retrying"
      sleep 5
  done
  aws s3 cp s3://${vault_cert_bucket}/ca.crt.pem $VAULT_TLS_CERT_DIR
  aws s3 cp s3://${vault_cert_bucket}/vault.crt.pem $VAULT_TLS_CERT_DIR

  # Set ownership and permissions
  sudo chown ubuntu $VAULT_TLS_CERT_DIR/*
  sudo chmod 600 $VAULT_TLS_CERT_DIR/*
  sudo /opt/vault/bin/update-certificate-store --cert-file-path $CA_TLS_CERT_FILE
}

# Send the log output from this script to user-data.log, syslog, and the console
# From: https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

download_vault_certs
write_data
write_nginx_config
get_ssl_certs

# These variables are passed in via Terraform template interpolation
/opt/consul/bin/run-consul --client --cluster-tag-key "${consul_cluster_tag_key}" --cluster-tag-value "${consul_cluster_tag_value}"
