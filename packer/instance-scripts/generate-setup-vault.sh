#!/bin/bash
set -eu -o pipefail

OUTPUT_FILE=/opt/vault/bin/setup-vault.sh

# Write the setup-vault script
cat << EOF > $OUTPUT_FILE
#!/bin/bash
set -eu -o pipefail

ROOT_TOKEN=\$1

OKTA_TOKEN=\$(cat /opt/vault/okta-api-token.txt)

OKTA_ORG="eximchain"
OKTA_BASE_URL="okta.com"

PLUGIN_PATH="/opt/vault/bin/plugins/guardian-plugin"
POLICY_DIR="/opt/vault/config/policies/"

# Login as root
vault login \$ROOT_TOKEN

# Enable & configure auth plugins
vault auth enable approle
vault auth enable okta
vault write auth/okta/config organization="\$OKTA_ORG" token="\$OKTA_TOKEN" base_url="\$OKTA_BASE_URL"

# Write the **Guardian**, **Enduser**, and **Maintainer** policies
vault policy write enduser \$POLICY_DIR/enduser.hcl
vault policy write guardian \$POLICY_DIR/guardian.hcl
vault policy write maintainer \$POLICY_DIR/maintainer.hcl

# Register the Guardian plugin
CHECKSUM=\$(sudo shasum -a 256 \$PLUGIN_PATH | awk '{print \$1}')
vault write sys/plugins/catalog/secret/guardian-plugin sha256=\$CHECKSUM command="guardian-plugin"

# Mount the Guardian plugin at /guardian
vault secrets enable -path=guardian -plugin-name=secret/guardian-plugin plugin

# Mount a secrets engine at /keys
vault secrets enable -path=keys kv

# Grant policies to appropriate Okta groups
vault write auth/okta/groups/vault-guardian-endusers policies=enduser
vault write auth/okta/groups/vault-guardian-maintainers policies=maintainer

# Create the Guardian AppRole
vault write auth/approle/role/guardian secret_id_num_uses=1 policies="guardian" secret_id_ttl="10m" secret_id_bound_cidrs="127.0.0.1/32" token_bound_cidrs="127.0.0.1/32"

# Update its RoleId to guardian-role-id
vault write auth/approle/role/guardian/role-id role_id="guardian-role-id"

# Get a SecretID, pass it into /guardian/authorize along with Okta creds
SECRET_ID=\$(vault write -force auth/approle/role/guardian/secret-id | awk 'FNR == 3 {print \$2}')
vault write guardian/authorize secret_id=\$SECRET_ID okta_url=\$OKTA_ORG okta_token=\$OKTA_TOKEN

# Revoke the root token to reduce security risk
vault token-revoke \$ROOT_TOKEN
EOF

# Give permission to run the script
sudo chown ubuntu $OUTPUT_FILE
sudo chmod 744 $OUTPUT_FILE
