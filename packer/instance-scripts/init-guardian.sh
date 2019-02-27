#!/bin/bash
set -u -o pipefail

function wait_for_successful_command {
    local COMMAND=$1

    $COMMAND
    until [ $? -eq 0 ]
    do
        sleep 5
        $COMMAND
    done
}

function generate_guardian_supervisor_config {
  local readonly VAULT_URL=$(cat /opt/guardian/info/vault-url.txt)
  local readonly QUORUM_URL=$(cat /opt/guardian/info/quorum-url.txt)
  local readonly DISABLE_AUTH=$(cat /opt/guardian/info/disable-authentication.txt)
  echo "[program:guardian]
command=sh -c '/opt/guardian/go/bin/eximchain-guardian server -vault-address=$VAULT_URL -quorum-address=$QUORUM_URL -disable-auth=$DISABLE_AUTH'
stdout_logfile=/opt/guardian/log/guardian-stdout.log
stderr_logfile=/opt/guardian/log/guardian-error.log
numprocs=1
autostart=true
autorestart=unexpected
stopsignal=INT
user=ubuntu
environment=GOPATH=/opt/guardian/go" | sudo tee /etc/supervisor/conf.d/guardian-supervisor.conf
}

function get_ssl_certs {
  local readonly ENABLE_HTTPS=$(cat /opt/guardian/info/enable-https.txt)
  if [ "$ENABLE_HTTPS" == "true" ]
  then
    # LetsEncrypt requires a webmaster email in case of issues.  Must specify custom domain
    # we want certs for.  Note that we only use custom b/c they don't give certs to .amazonaws.com
    # domains.  Including the --cert-name option ensures that we know what directory the keys
    # are placed in, and it tells LetsEncrypt which nginx config to update.
    local readonly CERT_WEBMASTER="louis@eximchain.com"
    local readonly DOMAIN=$(cat /opt/guardian/info/custom-domain.txt)
    wait_for_successful_command "sudo certbot --cert-name guardian --nginx --noninteractive --agree-tos -m $CERT_WEBMASTER -d $DOMAIN"
  fi
}

get_ssl_certs

# Generate singleton geth keypair for testing
GETH_PW=$(uuidgen -r)
ADDRESS=0x$(echo -ne "$GETH_PW\n$GETH_PW\n" | geth account new | grep Address | awk '{ gsub("{|}", "") ; print $2 }')
PRIV_KEY=$(cat /home/ubuntu/.ethereum/keystore/*$(echo $ADDRESS | cut -d 'x' -f2))

# Wait for operator to initialize and unseal vault
wait_for_successful_command 'vault init -check'
wait_for_successful_command 'vault status'

# Wait for vault to be fully configured by the root user
wait_for_successful_command 'vault auth -method=aws'

wait_for_successful_command "vault write keys/singleton password=$GETH_PW address=$ADDRESS key=$PRIV_KEY"

# Replace the config that runs this with one that runs the guardian itself
generate_guardian_supervisor_config
sudo rm /etc/supervisor/conf.d/init-guardian-supervisor.conf
sudo supervisorctl reread
sudo supervisorctl update
