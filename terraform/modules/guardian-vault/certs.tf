# ---------------------------------------------------------------------------------------------------------------------
# SELF-SIGNED CERTIFICATES FOR VAULT LOCAL LISTENER
# ---------------------------------------------------------------------------------------------------------------------
module "cert_tool" {
  source = "../cert-tool"

  ca_public_key_file_path = "${path.module}/certs/ca.crt.selfsigned.pem"
  public_key_file_path    = "${path.module}/certs/vault.crt.selfsigned.pem"
  private_key_file_path   = "${path.module}/certs/vault.key.selfsigned.pem"
  owner                   = "${var.cert_owner}"
  organization_name       = "${var.cert_org_name}"
  ca_common_name          = "guardian-vault cert authority"
  common_name             = "guardian cert network"
  dns_names               = ["${local.custom_domain}", "localhost"]
  ip_addresses            = ["127.0.0.1"]
  validity_period_hours   = 8760
}

# ---------------------------------------------------------------------------------------------------------------------
# LET'S ENCRYPT CERTIFICATES FOR VAULT REMOTE LISTENER
# ---------------------------------------------------------------------------------------------------------------------
provider "acme" {
  version = "~> 1.1"

  server_url = "${var.letsencrypt_acme_server}"
}

provider "tls" {
  version = "~> 1.2"
}

resource "tls_private_key" "letsencrypt" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

resource "acme_registration" "letsencrypt_registration" {
  account_key_pem = "${tls_private_key.letsencrypt.private_key_pem}"
  email_address   = "${var.letsencrypt_webmaster}"
}

resource "acme_certificate" "letsencrypt" {
  account_key_pem = "${acme_registration.letsencrypt_registration.account_key_pem}"
  common_name     = "${local.custom_domain}"
  key_type        = "4096"

  dns_challenge {
    provider = "route53"
  }
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
resource "aws_s3_bucket_object" "vault_selfsigned_ca_public_key" {
  key                    = "ca.crt.selfsigned.pem"
  bucket                 = "${aws_s3_bucket.vault_certs.bucket}"
  source                 = "${module.cert_tool.ca_public_key_file_path}"
  server_side_encryption = "aws:kms"

  depends_on = ["module.cert_tool"]
}

resource "aws_s3_bucket_object" "vault_selfsigned_public_key" {
  key                    = "vault.crt.selfsigned.pem"
  bucket                 = "${aws_s3_bucket.vault_certs.bucket}"
  source                 = "${module.cert_tool.public_key_file_path}"
  server_side_encryption = "aws:kms"

  depends_on = ["module.cert_tool"]
}

resource "aws_s3_bucket_object" "vault_selfsigned_private_key" {
  key                    = "vault.key.selfsigned.pem"
  bucket                 = "${aws_s3_bucket.vault_certs.bucket}"
  source                 = "${module.cert_tool.private_key_file_path}"
  server_side_encryption = "aws:kms"

  depends_on = ["module.cert_tool"]
}

resource "aws_s3_bucket_object" "vault_letsencrypt_ca_public_key" {
  key                    = "chain.pem"
  bucket                 = "${aws_s3_bucket.vault_certs.bucket}"
  content                = "${acme_certificate.letsencrypt.issuer_pem}"
  server_side_encryption = "aws:kms"
}

resource "aws_s3_bucket_object" "vault_letsencrypt_public_key" {
  key                    = "cert.pem"
  bucket                 = "${aws_s3_bucket.vault_certs.bucket}"
  content                = "${acme_certificate.letsencrypt.certificate_pem}"
  server_side_encryption = "aws:kms"
}

resource "aws_s3_bucket_object" "vault_letsencrypt_private_key" {
  key                    = "privkey.pem"
  bucket                 = "${aws_s3_bucket.vault_certs.bucket}"
  content                = "${acme_certificate.letsencrypt.private_key_pem}"
  server_side_encryption = "aws:kms"
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
