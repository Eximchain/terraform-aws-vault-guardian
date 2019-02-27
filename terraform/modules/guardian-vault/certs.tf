# ---------------------------------------------------------------------------------------------------------------------
# CERTIFICATES FOR VAULT
# ---------------------------------------------------------------------------------------------------------------------
module "cert_tool" {
  source = "../cert-tool"

  ca_public_key_file_path = "${path.module}/certs/ca.crt.pem"
  public_key_file_path    = "${path.module}/certs/vault.crt.pem"
  private_key_file_path   = "${path.module}/certs/vault.key.pem"
  owner                   = "${var.cert_owner}"
  organization_name       = "${var.cert_org_name}"
  ca_common_name          = "guardian-vault cert authority"
  common_name             = "guardian cert network"
  dns_names               = ["${aws_lb.guardian_vault.dns_name}"]
  ip_addresses            = ["127.0.0.1"]
  validity_period_hours   = 8760
}

# ---------------------------------------------------------------------------------------------------------------------
# S3 BUCKET FOR STORING CERTS
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "vault_certs" {
  bucket_prefix = "guardian-vault-certs-"
  acl           = "private"
}

# ---------------------------------------------------------------------------------------------------------------------
# UPLOAD CERTS TO S3
# TODO: Encrypt end-to-end with KMS
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket_object" "vault_ca_public_key" {
  key                    = "ca.crt.pem"
  bucket                 = "${aws_s3_bucket.vault_certs.bucket}"
  source                 = "${module.cert_tool.ca_public_key_file_path}"
  server_side_encryption = "aws:kms"

  depends_on = ["module.cert_tool"]
}

resource "aws_s3_bucket_object" "vault_public_key" {
  key                    = "vault.crt.pem"
  bucket                 = "${aws_s3_bucket.vault_certs.bucket}"
  source                 = "${module.cert_tool.public_key_file_path}"
  server_side_encryption = "aws:kms"

  depends_on = ["module.cert_tool"]
}

resource "aws_s3_bucket_object" "vault_private_key" {
  key                    = "vault.key.pem"
  bucket                 = "${aws_s3_bucket.vault_certs.bucket}"
  source                 = "${module.cert_tool.private_key_file_path}"
  server_side_encryption = "aws:kms"

  depends_on = ["module.cert_tool"]
}

resource "null_resource" "vault_cert_s3_upload" {
  depends_on = ["aws_s3_bucket_object.vault_ca_public_key", "aws_s3_bucket_object.vault_public_key", "aws_s3_bucket_object.vault_private_key"]
}

# ---------------------------------------------------------------------------------------------------------------------
# STORE CERTS IN IAM
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_server_certificate" "vault_certs" {
  name_prefix       = "guardian-vault-cert-"
  certificate_body  = "${module.cert_tool.public_key}"
  certificate_chain = "${module.cert_tool.ca_public_key}"
  private_key       = "${module.cert_tool.private_key}"

  depends_on = ["module.cert_tool"]
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM POLICY TO ACCESS CERT BUCKET
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_policy" "vault_cert_access" {
  name_prefix = "guardian-vault-cert-access-"
  description = "Allow read access to the vault cert bucket"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:ListBucket"],
    "Resource": ["${aws_s3_bucket.vault_certs.arn}"]
  },{
    "Effect": "Allow",
    "Action": ["s3:GetObject"],
    "Resource": ["${aws_s3_bucket.vault_certs.arn}/*"]
  }]
}
EOF
}

resource "aws_iam_role_policy_attachment" "vault_cert_access" {
  role       = "${aws_iam_role.vault_cluster.id}"
  policy_arn = "${aws_iam_policy.vault_cert_access.arn}"
}
