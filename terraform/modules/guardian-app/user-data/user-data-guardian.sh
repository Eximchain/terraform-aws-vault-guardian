#!/bin/bash
# This script is meant to be run in the User Data of each EC2 Instance while it's booting. The script uses the
# run-consul script to configure and start Consul in server mode. Note that this script assumes it's running in an AMI
# built from the Packer template in examples/vault-consul-ami/vault-consul.json.

set -eu

readonly BASH_PROFILE_FILE="/home/ubuntu/.bash_profile"
readonly VAULT_TLS_CERT_DIR="/opt/vault/tls"
readonly CA_TLS_CERT_FILE="$VAULT_TLS_CERT_DIR/ca.crt.pem"

readonly ETHCONNECT_TOPIC_IN="ethconnect-eximchain-in"
readonly ETHCONNECT_TOPIC_OUT="ethconnect-eximchain-out"

# This is necessary to retrieve the address for vault
echo "export VAULT_ADDR=https://${vault_dns}:${vault_port}" >> $BASH_PROFILE_FILE
source $BASH_PROFILE_FILE

sleep 60

function write_data {
  echo "${ethconnect_webhook_port}" | sudo tee /opt/guardian/info/ethconnect-webhook-port.txt > /dev/null 2>&1
  echo "${ethconnect_always_manage_nonce}" | sudo tee /opt/guardian/info/ethconnect-always-manage-nonce.txt > /dev/null 2>&1
  echo "${ethconnect_max_in_flight}" | sudo tee /opt/guardian/info/ethconnect-max-in-flight.txt > /dev/null 2>&1
  echo "${ethconnect_max_tx_wait_time}" | sudo tee /opt/guardian/info/ethconnect-max-tx-wait-time.txt > /dev/null 2>&1
  echo "${ccloud_broker}" | sudo tee /opt/guardian/info/ccloud-broker-url.txt > /dev/null 2>&1
  echo "${ccloud_api_key}" | sudo tee /opt/guardian/info/ccloud-api-key.txt > /dev/null 2>&1
  echo "${ccloud_api_secret}" | sudo tee /opt/guardian/info/ccloud-api-secret.txt > /dev/null 2>&1
  echo "$ETHCONNECT_TOPIC_IN" | sudo tee /opt/guardian/info/ethconnect-topic-in.txt > /dev/null 2>&1
  echo "$ETHCONNECT_TOPIC_OUT" | sudo tee /opt/guardian/info/ethconnect-topic-out.txt > /dev/null 2>&1
  echo "${mongo_connection_url}" | sudo tee /opt/guardian/info/mongo-connection-url.txt > /dev/null 2>&1
  echo "${mongo_database_name}" | sudo tee /opt/guardian/info/mongo-database-name.txt > /dev/null 2>&1
  echo "${mongo_collection_name}" | sudo tee /opt/guardian/info/mongo-collection-name.txt > /dev/null 2>&1
  echo "${mongo_max_receipts}" | sudo tee /opt/guardian/info/mongo-max-receipts.txt > /dev/null 2>&1
  echo "${mongo_query_limit}" | sudo tee /opt/guardian/info/mongo-query-limit.txt > /dev/null 2>&1
  echo "${disable_authentication}" | sudo tee /opt/guardian/info/disable-authentication.txt > /dev/null 2>&1
  echo "${custom_domain}" | sudo tee /opt/guardian/info/custom-domain.txt > /dev/null 2>&1
  echo "${enable_https}" | sudo tee /opt/guardian/info/enable-https.txt > /dev/null 2>&1
}

function initialize_ccloud {
  local readonly BROKER=$(cat /opt/guardian/info/ccloud-broker-url.txt)
  local readonly API_KEY=$(cat /opt/guardian/info/ccloud-api-key.txt)
  local readonly API_SECRET=$(cat /opt/guardian/info/ccloud-api-secret.txt)

  if [ "$BROKER" != "" ] && [ "$API_KEY" != "" ] && [ "$API_SECRET" != "" ]
  then
    printf "$BROKER\n$API_KEY\n$API_SECRET\n" | sudo -u ubuntu ccloud init
  else
    echo "No Confluence Cloud configuration data found, skipping ccloud config."
  fi
}

function write_nginx_config {
  sudo rm -rf /etc/nginx/sites-enabled/default
  local readonly HOSTNAME="$(curl http://169.254.169.254/latest/meta-data/public-hostname)"
  local readonly HTTP_PORT="80"
  local readonly GOKIT_URL="http://localhost:8080"
  if [ "${using_custom_domain}" == "true" ]
  then
    local readonly SERVER_NAME="${custom_domain} $HOSTNAME"
  else
    local readonly SERVER_NAME="$HOSTNAME"
  fi
  echo "
  server {
    listen $HTTP_PORT;
    server_name $SERVER_NAME;
    location / {
      proxy_pass \"$GOKIT_URL\";
    }
  }" | sudo tee /etc/nginx/sites-available/guardian > /dev/null 2>&1
  sudo ln -s /etc/nginx/sites-available/guardian /etc/nginx/sites-enabled/guardian
  sudo service nginx restart
}

function write_ethconnect_config {
  local readonly TOPIC_IN=$(cat /opt/guardian/info/ethconnect-topic-in.txt)
  local readonly TOPIC_OUT=$(cat /opt/guardian/info/ethconnect-topic-out.txt)

  local readonly BROKER=$(cat /opt/guardian/info/ccloud-broker-url.txt)
  local readonly SASL_PASSWORD=$(cat /opt/guardian/info/ccloud-api-secret.txt)
  local readonly SASL_USERNAME=$(cat /opt/guardian/info/ccloud-api-key.txt)
  local readonly NODE_URL=$(cat /opt/guardian/info/quorum-url.txt)

  local readonly WEBHOOK_PORT=$(cat /opt/guardian/info/ethconnect-webhook-port.txt)
  local readonly MAX_IN_FLIGHT=$(cat /opt/guardian/info/ethconnect-max-in-flight.txt)
  local readonly MAX_TX_WAIT_TIME=$(cat /opt/guardian/info/ethconnect-max-tx-wait-time.txt)
  local readonly ALWAYS_MANAGE_NONCE=$(cat /opt/guardian/info/ethconnect-always-manage-nonce.txt)

  local readonly MONGO_URL=$(cat /opt/guardian/info/mongo-connection-url.txt)
  local readonly MONGO_DATABASE=$(cat /opt/guardian/info/mongo-database-name.txt)
  local readonly MONGO_COLLECTION=$(cat /opt/guardian/info/mongo-collection-name.txt)
  local readonly MONGO_MAX_DOCS=$(cat /opt/guardian/info/mongo-max-receipts.txt)
  local readonly MONGO_QUERY_LIMIT=$(cat /opt/guardian/info/mongo-query-limit.txt)

  local readonly HOSTNAME=$(curl http://169.254.169.254/latest/meta-data/public-hostname)

  local readonly CLIENT_ID=$(uuidgen -r)
  local readonly CONSUMER_GROUP=$(uuidgen -r)

  echo "kafka:
  kafka-to-eximchain:
    kafka:
      brokers:
      - $BROKER
      clientID: $CLIENT_ID
      consumerGroup: $CONSUMER_GROUP
      sasl:
        Password: $SASL_PASSWORD
        Username: $SASL_USERNAME
      tls:
        caCertsFile: \"\"
        clientCertsFile: \"\"
        clientKeyFile: \"\"
        enabled: true
        insecureSkipVerify: false
      topicIn: $TOPIC_IN
      topicOut: $TOPIC_OUT
    maxInFlight: $MAX_IN_FLIGHT
    maxTXWaitTime: $MAX_TX_WAIT_TIME
    alwaysManageNonce: $ALWAYS_MANAGE_NONCE
    rpc:
      url: $NODE_URL
webhooks:
  webhooks-to-kafka:
    http:
      localAddr: $HOSTNAME
      port: $WEBHOOK_PORT
      tls:
        caCertsFile: \"\"
        clientCertsFile: \"\"
        clientKeyFile: \"\"
        enabled: true
        insecureSkipVerify: false
    kafka:
      brokers:
      - $BROKER
      clientID: $CLIENT_ID
      consumerGroup: $CONSUMER_GROUP
      topicIn: $TOPIC_IN
      topicOut: $TOPIC_OUT
      sasl:
        Password: $SASL_PASSWORD
        Username: $SASL_USERNAME
      tls:
        caCertsFile: \"\"
        clientCertsFile: \"\"
        clientKeyFile: \"\"
        enabled: true
        insecureSkipVerify: false
    mongodb:
      collection: $MONGO_COLLECTION
      database: $MONGO_DATABASE
      maxDocs: $MONGO_MAX_DOCS
      queryLimit: $MONGO_QUERY_LIMIT
      url: $MONGO_URL" | sudo tee /opt/guardian/ethconnect-config.yml
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
initialize_ccloud
write_ethconnect_config
write_nginx_config

# These variables are passed in via Terraform template interpolation
/opt/consul/bin/run-consul --client --cluster-tag-key "${consul_cluster_tag_key}" --cluster-tag-value "${consul_cluster_tag_value}"

/opt/guardian/bin/generate-run-init-guardian ${vault_dns} ${vault_port}
/opt/guardian/bin/run-init-guardian
