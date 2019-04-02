# ---------------------------------------------------------------------------------------------------------------------
# S3 DATA SOURCES FOR FETCHING CERT
# ---------------------------------------------------------------------------------------------------------------------
data "aws_s3_bucket_object" "server_certificate" {
  count = "${var.cert_bucket_exists ? 1 : 0}"
  bucket = "${var.vault_cert_bucket_name}"
  key    = "vault.crt.pem"
}

data "aws_s3_bucket_object" "ca_certificate" {
  count = "${var.cert_bucket_exists ? 1 : 0}"
  bucket = "${var.vault_cert_bucket_name}"
  key    = "ca.crt.pem"
}

data "aws_s3_bucket_object" "private_key" {
  count = "${var.cert_bucket_exists ? 1 : 0}"
  bucket = "${var.vault_cert_bucket_name}"
  key    = "vault.key.pem"
}

resource "null_resource" "certs_available" {
  depends_on = ["data.aws_s3_bucket_object.server_certificate"]
}

# ---------------------------------------------------------------------------------------------------------------------
# STORE CERTS IN IAM
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_server_certificate" "vault_certs" {
  name_prefix       = "guardian-vault-cert-"
  certificate_body  = "${data.aws_s3_bucket_object.server_certificate.body}"
  certificate_chain = "${data.aws_s3_bucket_object.ca_certificate.body}"
  private_key       = "${data.aws_s3_bucket_object.private_key.body}"
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
    "Resource": ["${var.vault_cert_bucket_arn}"]
  },{
    "Effect": "Allow",
    "Action": ["s3:GetObject"],
    "Resource": ["${var.vault_cert_bucket_arn}/*"]
  }]
}
EOF
}

resource "aws_iam_role_policy_attachment" "vault_cert_access" {
  role       = "${aws_iam_role.vault_cluster.id}"
  policy_arn = "${aws_iam_policy.vault_cert_access.arn}"
}
