# ---------------------------------------------------------------------------------------------------------------------
# PROVIDERS
# ---------------------------------------------------------------------------------------------------------------------
provider "aws" {
  version = "~> 1.5"

  region  = "${var.aws_region}"
}

provider "tls" {
  version = "~> 1.0"
}

provider "template" {
  version = "~> 1.0"
}

# ---------------------------------------------------------------------------------------------------------------------
# KEY PAIR FOR ALL INSTANCES
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_key_pair" "auth" {
  key_name_prefix = "guardian-"
  public_key      = "${var.public_key}"
}

# ---------------------------------------------------------------------------------------------------------------------
# TRANSACTION EXECUTOR POLICY
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_policy" "guardian" {
  name_prefix = "eximchain-guardian-"
  description = "A policy for a transaction executor"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ec2:DescribeInstances",
      "ec2:DescribeImages",
      "ec2:DescribeTags",
      "ec2:DescribeSnapshots"
    ],
    "Resource": "*"
  },{
    "Effect": "Allow",
    "Action": ["s3:ListBucket"],
    "Resource": ["${var.vault_cert_bucket_arn}"]
  },{
    "Effect": "Allow",
    "Action": ["s3:GetObject"],
    "Resource": [
      "${var.vault_cert_bucket_arn}/ca.crt.pem",
      "${var.vault_cert_bucket_arn}/vault.crt.pem"
    ]
  }]
}
EOF
}

# ---------------------------------------------------------------------------------------------------------------------
# TRANSACTION EXECUTOR NETWORKING
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_subnet" "guardian" {
  vpc_id                  = "${var.aws_vpc}"
  availability_zone       = "${var.availability_zone}"
  cidr_block              = "${cidrsubnet(var.base_subnet_cidr, 3, count.index)}"
  map_public_ip_on_launch = true
}

# ---------------------------------------------------------------------------------------------------------------------
# DNS RECORD
# ---------------------------------------------------------------------------------------------------------------------
locals {
  using_custom_domain = "${var.subdomain_name != "" && var.root_domain != ""}"
  custom_domain       = "${var.subdomain_name}.${var.root_domain}"
  using_https         = "${var.enable_https == "true"}"
}

data "aws_route53_zone" "domain" {
  count = "${local.using_custom_domain ? 1 : 0}"
  name  = "${var.root_domain}."
}

resource "aws_route53_record" "guardian" {
  count = "${local.using_custom_domain ? 1 : 0}"

  zone_id                  = "${data.aws_route53_zone.domain.zone_id}"
  name                     = "${local.custom_domain}"
  type                     = "A"
  ttl                      = "300"
  records                  = ["${aws_instance.guardian.public_ip}"]
}

# ---------------------------------------------------------------------------------------------------------------------
# TRANSACTION EXECUTOR NODE
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_instance" "guardian" {
  connection {
    # The default username for our AMI
    user = "ubuntu"

    # The connection will use the local SSH agent for authentication if this is empty.
    private_key = "${var.private_key}"

    # Must explicitly specify host, auto-inference fails for destroy-time provisioner
    host = "${aws_instance.guardian.public_dns}"
  }

  instance_type = "${var.guardian_instance_type}"

  ami       = "${var.guardian_ami == "" ? element(coalescelist(data.aws_ami.guardian.*.id, list("")), 0) : var.guardian_ami}"
  user_data = "${data.template_file.user_data_guardian.rendered}"

  key_name = "${aws_key_pair.auth.id}"

  iam_instance_profile = "${aws_iam_instance_profile.guardian.name}"

  vpc_security_group_ids = ["${aws_security_group.guardian.id}"]
  subnet_id              = "${element(aws_subnet.guardian.*.id, 0)}"

  tags {
    Name = "guardian"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get -y update",
      "mkdir /opt/guardian/info",
      "echo 'https://${var.vault_dns}:${var.vault_port}' > /opt/guardian/info/vault-url.txt",
      "echo 'http://${var.quorum_dns}:${var.quorum_port}' > /opt/guardian/info/quorum-url.txt"
    ]
  }

  depends_on = ["aws_security_group_rule.guardian_ssh","aws_security_group_rule.guardian_egress"]

  provisioner "remote-exec" {
    when = "destroy"
    inline = [
      "echo AWS VPC Route ID is ${var.aws_route}, ensuring it still exists for revoking certificates",
      "/opt/guardian/bin/revoke-https-cert.sh"
    ]
  }
}

data "aws_ami" "guardian" {
  count = "${var.guardian_ami == "" ? 1 : 0}"

  most_recent = true
  owners      = ["037794263736"]

  filter {
    name   = "name"
    values = ["eximchain-guardian-*"]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH TRANSACTION EXECUTOR NODE WHEN IT'S BOOTING
# This script will configure and start the Consul Agent
# ---------------------------------------------------------------------------------------------------------------------
data "template_file" "user_data_guardian" {
  template = "${file("${path.module}/user-data/user-data-guardian.sh")}"

  vars {
    vault_dns  = "${var.vault_dns}"
    vault_port = "${var.vault_port}"

    consul_cluster_tag_key   = "${var.consul_cluster_tag_key}"
    consul_cluster_tag_value = "${var.consul_cluster_tag_value}"

    vault_cert_bucket = "${var.vault_cert_bucket_name}"

    disable_authentication = "${var.disable_authentication}"

    ethconnect_webhook_port        = "${var.ethconnect_webhook_port}"
    ethconnect_always_manage_nonce = "${var.ethconnect_always_manage_nonce}"
    ethconnect_max_in_flight       = "${var.ethconnect_max_in_flight}"
    ethconnect_max_tx_wait_time    = "${var.ethconnect_max_tx_wait_time}"

    ccloud_broker     = "${var.ccloud_broker}"
    ccloud_api_key    = "${var.ccloud_api_key}"
    ccloud_api_secret = "${var.ccloud_api_secret}"

    mongo_connection_url      = "${var.mongo_connection_url}"
    mongo_database_name       = "${var.mongo_database_name}"
    mongo_collection_name     = "${var.mongo_collection_name}"
    mongo_max_receipts        = "${var.mongo_max_receipts}"
    mongo_query_limit         = "${var.mongo_query_limit}"

    enable_https        = "${var.enable_https}"
    using_custom_domain = "${local.using_custom_domain}"
    custom_domain       = "${local.custom_domain}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# TRANSACTION EXECUTOR SECURITY GROUP
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_security_group" "guardian" {
  name        = "guardian"
  description = "Used for transaction executor"
  vpc_id      = "${var.aws_vpc}"
}

resource "aws_security_group_rule" "guardian_ssh" {
  security_group_id = "${aws_security_group.guardian.id}"
  type              = "ingress"

  from_port = 22
  to_port   = 22
  protocol  = "tcp"

  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "guardian_rpc_cidr_access_http" {
  count = "${length(var.rpc_api_cidrs) == 0 ? 0 : 1}"

  security_group_id = "${aws_security_group.guardian.id}"
  type              = "ingress"

  from_port = 80
  to_port   = 80
  protocol  = "tcp"

  cidr_blocks = "${var.rpc_api_cidrs}"
}

resource "aws_security_group_rule" "guardian_rpc_security_group_access_http" {
  count = "${length(var.rpc_api_security_groups)}"

  security_group_id = "${aws_security_group.guardian.id}"
  type              = "ingress"

  from_port = 80
  to_port   = 80
  protocol  = "tcp"

  source_security_group_id = "${element(var.rpc_api_security_groups, count.index)}"
}

resource "aws_security_group_rule" "guardian_rpc_cidr_access_https" {
  count = "${local.using_https && length(var.rpc_api_cidrs) > 0 ? 1 : 0}"

  security_group_id = "${aws_security_group.guardian.id}"
  type              = "ingress"

  from_port = 443
  to_port   = 443
  protocol  = "tcp"

  cidr_blocks = "${var.rpc_api_cidrs}"
}

resource "aws_security_group_rule" "guardian_rpc_security_group_access_https" {
  count = "${local.using_https ? length(var.rpc_api_security_groups) : 0}"

  security_group_id = "${aws_security_group.guardian.id}"
  type              = "ingress"

  from_port = 443
  to_port   = 443
  protocol  = "tcp"

  source_security_group_id = "${element(var.rpc_api_security_groups, count.index)}"
}

resource "aws_security_group_rule" "guardian_ethconnect_cidr_access" {
  count = "${length(var.ethconnect_api_cidrs) == 0 ? 0 : 1}"

  security_group_id = "${aws_security_group.guardian.id}"
  type              = "ingress"

  from_port = "${var.ethconnect_webhook_port}"
  to_port   = "${var.ethconnect_webhook_port}"
  protocol  = "tcp"

  cidr_blocks = "${var.ethconnect_api_cidrs}"
}

resource "aws_security_group_rule" "guardian_ethconnect_security_group_access" {
  count = "${length(var.ethconnect_api_security_groups)}"

  security_group_id = "${aws_security_group.guardian.id}"
  type              = "ingress"

  from_port = "${var.ethconnect_webhook_port}"
  to_port   = "${var.ethconnect_webhook_port}"
  protocol  = "tcp"

  source_security_group_id = "${element(var.ethconnect_api_security_groups, count.index)}"
}

resource "aws_security_group_rule" "guardian_egress" {
  security_group_id = "${aws_security_group.guardian.id}"
  type              = "egress"

  from_port = 0
  to_port   = 0
  protocol  = "-1"

  cidr_blocks = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------------------------------------------------
# TRANSACTION EXECUTOR IAM ROLE
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_role" "guardian" {
  name_prefix = "eximchain-guardian-"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Action": "sts:AssumeRole",
    "Principal": {
      "Service": "ec2.amazonaws.com"
    },
    "Effect": "Allow",
    "Sid": ""
  }]
}
EOF
}

# ---------------------------------------------------------------------------------------------------------------------
# TRANSACTION EXECUTOR IAM POLICY ATTACHMENT AND INSTANCE PROFILE
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "guardian" {
  role       = "${aws_iam_role.guardian.name}"
  policy_arn = "${aws_iam_policy.guardian.arn}"
}

resource "aws_iam_instance_profile" "guardian" {
  name = "${aws_iam_role.guardian.name}"
  role = "${aws_iam_role.guardian.name}"
}
