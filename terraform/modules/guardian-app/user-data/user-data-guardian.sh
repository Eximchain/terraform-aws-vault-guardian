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
    location /v1/guardian {
      if (\$request_method = 'OPTIONS') {
        # Tell client that this pre-flight info is valid for 20 days
        add_header 'Access-Control-Allow-Origin' '\$http_origin' always;
        add_header 'Access-Control-Allow_Credentials' 'true' always;
        add_header 'Access-Control-Allow-Methods' 'GET,POST,PUT,OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'Authorization,Accept,DNT,Origin,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
        add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;
        add_header 'Access-Control-Max-Age' 1728000;
        add_header 'Content-Type' 'text/plain charset=UTF-8';
        add_header 'Content-Length' 0;
        return 204;
      }
      add_header 'Access-Control-Allow-Origin' '\$http_origin' always;
      add_header 'Access-Control-Allow_Credentials' 'true' always;
      add_header 'Access-Control-Allow-Methods' 'GET,POST,PUT,OPTIONS' always;
      add_header 'Access-Control-Allow-Headers' 'Authorization,Accept,DNT,Origin,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
      add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;
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

function upload_cert {
  local FILENAME=$1
  local S3_KEY=$2
  sudo aws s3 cp /etc/letsencrypt/archive/guardian/${FILENAME} s3://${vault_cert_bucket}/${S3_KEY} --sse aws:kms
}

function upload_ssl_certs {
  aws configure set s3.signature_version s3v4
  upload_cert privkey1.pem vault.key.pem
  upload_cert fullchain1.pem full.crt.pem
  upload_cert cert1.pem vault.crt.pem
  upload_cert chain1.pem ca.crt.pem
}

# Send the log output from this script to user-data.log, syslog, and the console
# From: https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

write_data
write_nginx_config
get_ssl_certs
upload_ssl_certs

# These variables are passed in via Terraform template interpolation
/opt/consul/bin/run-consul --client --cluster-tag-key "${consul_cluster_tag_key}" --cluster-tag-value "${consul_cluster_tag_value}"
