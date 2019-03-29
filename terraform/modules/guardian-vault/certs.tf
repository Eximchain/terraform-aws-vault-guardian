# ---------------------------------------------------------------------------------------------------------------------
# S3 DATA SOURCES FOR FETCHING CERT
# ---------------------------------------------------------------------------------------------------------------------
data "aws_s3_bucket_object" "server_certificate" {
  bucket = "${var.vault_cert_bucket_name}"
  key    = "vault.crt.pem"
}

data "aws_s3_bucket_object" "ca_certificate" {
  bucket = "${var.vault_cert_bucket_name}"
  key    = "ca.crt.pem"
}

data "aws_s3_bucket_object" "private_key" {
  bucket = "${var.vault_cert_bucket_name}"
  key    = "vault.key.pem"
}

# ---------------------------------------------------------------------------------------------------------------------
# STORE CERTS IN IAM
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_server_certificate" "vault_certs" {
  name_prefix       = "guardian-vault-cert-"
  certificate_body  = "${aws_s3_bucket_object.server_certificate.body}"
  certificate_chain = "${aws_s3_bucket_object.ca_certificate.body}"
  private_key       = "${aws_s3_bucket_object.private_key.body}"

  depends_on = ["aws_s3_bucket_object.public_key", "aws_s3_bucket_object.ca_public_key", "aws_s3_bucket_object.private_key"]
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
