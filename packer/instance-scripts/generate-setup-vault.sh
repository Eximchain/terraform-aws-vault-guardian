#!/bin/bash
set -eu -o pipefail

OUTPUT_FILE=/opt/vault/bin/setup-vault.sh
AWS_ACCOUNT_ID=$(curl http://169.254.169.254/latest/meta-data/iam/info | jq .InstanceProfileArn | cut -d: -f5)

GUARDIAN_ROLE_NAME=$1
EXIMCHAIN_NODE_ROLE_NAME=$2

# Write the setup-vault script
cat << EOF > $OUTPUT_FILE
#!/bin/bash
set -eu -o pipefail

# Takes the root token as an argument
# Sets up the vault permissions and deletes the root token when it's done
ROOT_TOKEN=\$1

# Authorize with the root token
vault auth \$ROOT_TOKEN

# Enable the aws auth backend
vault auth-enable aws

# Enable audit logging
AUDIT_LOG=/opt/vault/log/audit.log
vault audit-enable file file_path=\$AUDIT_LOG

# Mount paths
vault mount -path=keys -default-lease-ttl=30 -description="Keys for the Transaction Executor" kv
vault mount -path=nodes -default-lease-ttl=30 -description="Keys for the Eximchain Node" kv

# Create policies
GUARDIAN_POLICY=/opt/vault/config/policies/guardian.hcl
EXIMCHAIN_NODE_POLICY=/opt/vault/config/policies/eximchain-node.hcl
vault policy-write guardian \$GUARDIAN_POLICY
vault policy-write eximchain_node \$EXIMCHAIN_NODE_POLICY

# Write policy to the roles used by instances
vault write auth/aws/role/$GUARDIAN_ROLE_NAME auth_type=iam policies=guardian bound_iam_principal_arn=arn:aws:iam::$AWS_ACCOUNT_ID:role/$GUARDIAN_ROLE_NAME
vault write auth/aws/role/$EXIMCHAIN_NODE_ROLE_NAME auth_type=iam policies=eximchain_node bound_iam_principal_arn=arn:aws:iam::$AWS_ACCOUNT_ID:role/$EXIMCHAIN_NODE_ROLE_NAME

# Revoke the root token to reduce security risk
vault token-revoke \$ROOT_TOKEN
EOF

# Give permission to run the script
sudo chown ubuntu $OUTPUT_FILE
sudo chmod 744 $OUTPUT_FILE
