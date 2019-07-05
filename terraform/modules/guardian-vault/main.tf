terraform {
  required_version = ">= 0.12"
}

# ---------------------------------------------------------------------------------------------------------------------
# PROVIDERS
# ---------------------------------------------------------------------------------------------------------------------
provider "aws" {
  version = "~> 2.18.0"

  region = var.aws_region
}

provider "template" {
  version = "~> 2.1.2"
}

# ---------------------------------------------------------------------------------------------------------------------
# KEY PAIR FOR ALL INSTANCES
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_key_pair" "auth" {
  key_name_prefix = "guardian-key-"
  public_key      = var.public_key
}

# ---------------------------------------------------------------------------------------------------------------------
# VAULT CLUSTER NETWORKING
# ---------------------------------------------------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "vault" {
  vpc_id                  = var.aws_vpc
  count                   = length(data.aws_availability_zones.available.names)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  cidr_block              = cidrsubnet(var.base_subnet_cidr, 3, count.index)
  map_public_ip_on_launch = true
}

# ---------------------------------------------------------------------------------------------------------------------
# LOAD BALANCER FOR VAULT
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_lb" "guardian_vault" {
  internal = false

  load_balancer_type = "network"

  subnets = aws_subnet.vault.*.id
}

resource "aws_lb_target_group" "guardian_vault" {
  name_prefix = "vault-"
  port        = var.vault_port
  protocol    = "TCP"
  vpc_id      = var.aws_vpc
}

resource "aws_lb_listener" "guardian_vault_ssl" {
  load_balancer_arn = aws_lb.guardian_vault.arn
  port              = var.vault_lb_port
  protocol          = "TCP"

  default_action {
    target_group_arn = aws_lb_target_group.guardian_vault.arn
    type             = "forward"
  }
}

resource "aws_lb_listener" "guardian_vault_direct" {
  load_balancer_arn = aws_lb.guardian_vault.arn
  port              = var.vault_port
  protocol          = "TCP"

  default_action {
    target_group_arn = aws_lb_target_group.guardian_vault.arn
    type             = "forward"
  }
}

resource "aws_lb_target_group" "vault_cluster_redirect" {
  name_prefix = "vclus-"
  port        = 8201
  protocol    = "TCP"
  vpc_id      = var.aws_vpc
}

resource "aws_lb_listener" "vault_cluster_redirect" {
  load_balancer_arn = aws_lb.guardian_vault.arn
  port              = 8201
  protocol          = "TCP"

  default_action {
    target_group_arn = aws_lb_target_group.vault_cluster_redirect.arn
    type             = "forward"
  }
}

data "aws_ami" "vault_consul" {
  count = var.vault_consul_ami == "" ? 1 : 0

  most_recent = true
  owners      = ["037794263736"]

  filter {
    name   = "name"
    values = ["eximchain-vault-guardian-*"]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DNS RECORD
# ---------------------------------------------------------------------------------------------------------------------
locals {
  custom_domain = "${var.subdomain_name}.${var.root_domain}"
}

data "aws_route53_zone" "domain" {
  name = "${var.root_domain}."
}

resource "aws_route53_record" "guardian" {
  zone_id = data.aws_route53_zone.domain.zone_id
  name    = local.custom_domain
  type    = "A"

  alias {
    name    = aws_lb.guardian_vault.dns_name
    zone_id = aws_lb.guardian_vault.zone_id

    evaluate_target_health = false
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# ALLOW VAULT CLUSTER TO USE AWS AUTH
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_policy" "allow_aws_auth" {
  name_prefix = "allow-vault-aws-auth-"
  description = "Allow authentication to vault by AWS mechanisms"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ec2:DescribeInstances",
      "iam:GetInstanceProfile",
      "iam:GetUser",
      "iam:GetRole"
    ],
    "Resource": "*"
  }]
}
EOF

}

resource "aws_iam_role_policy_attachment" "allow_aws_auth" {
  role = aws_iam_role.vault_cluster.id
  policy_arn = aws_iam_policy.allow_aws_auth.arn
}

# ---------------------------------------------------------------------------------------------------------------------
# ATTACH IAM POLICIES FOR CONSUL
# To allow our Vault servers to automatically discover the Consul servers, we need to give them the IAM permissions from
# the Consul AWS Module's consul-iam-policies module.
# ---------------------------------------------------------------------------------------------------------------------
module "consul_iam_policies_servers" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-iam-policies?ref=v0.1.0"

  iam_role_id = aws_iam_role.vault_cluster.id
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH VAULT SERVER WHEN IT'S BOOTING
# This script will configure and start Vault
# ---------------------------------------------------------------------------------------------------------------------
data "template_file" "user_data_vault_cluster" {
  template = file("${path.module}/user-data/user-data-vault.sh")

  vars = {
    aws_region = var.aws_region
    s3_bucket_name = aws_s3_bucket.guardian_vault.id
    consul_cluster_tag_key = module.consul_cluster.cluster_tag_key
    consul_cluster_tag_value = module.consul_cluster.cluster_tag_value
    vault_cert_bucket = aws_s3_bucket.vault_certs.bucket
    okta_api_token = var.okta_api_token
    vault_api_addr = local.custom_domain
    vault_log_level = var.vault_log_level
  }

  # user-data needs to download these objects
  depends_on = [
    aws_s3_bucket_object.vault_selfsigned_ca_public_key,
    aws_s3_bucket_object.vault_selfsigned_public_key,
    aws_s3_bucket_object.vault_selfsigned_private_key,
    aws_s3_bucket_object.vault_letsencrypt_ca_public_key,
    aws_s3_bucket_object.vault_letsencrypt_public_key,
    aws_s3_bucket_object.vault_letsencrypt_private_key,
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE CONSUL SERVER CLUSTER
# ---------------------------------------------------------------------------------------------------------------------
module "consul_cluster" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-cluster?ref=v0.7.0"

  cluster_name  = "quorum-consul"
  cluster_size  = var.consul_cluster_size
  instance_type = var.consul_instance_type

  # The EC2 Instances will use these tags to automatically discover each other and form a cluster
  cluster_tag_key   = "consul-cluster"
  cluster_tag_value = "guardian-consul"

  ami_id    = var.vault_consul_ami == "" ? element(coalescelist(data.aws_ami.vault_consul.*.id, [""]), 0) : var.vault_consul_ami
  user_data = data.template_file.user_data_consul.rendered

  vpc_id     = var.aws_vpc
  subnet_ids = aws_subnet.vault.*.id

  # To make testing easier, we allow Consul and SSH requests from any IP address here but in a production
  # deployment, we strongly recommend you limit this to the IP address ranges of known, trusted servers inside your VPC.

  allowed_ssh_cidr_blocks     = ["0.0.0.0/0"]
  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
  ssh_key_name                = aws_key_pair.auth.id
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH CONSUL SERVER WHEN IT'S BOOTING
# This script will configure and start Consul
# ---------------------------------------------------------------------------------------------------------------------
data "template_file" "user_data_consul" {
  template = file("${path.module}/user-data/user-data-consul.sh")

  vars = {
    consul_cluster_tag_key = module.consul_cluster.cluster_tag_key
    consul_cluster_tag_value = module.consul_cluster.cluster_tag_value
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# EXPORT CURRENT VAULT SERVER IPS
# These servers may change over time but you can use an arbitrary server for initial setup
# ---------------------------------------------------------------------------------------------------------------------
data "aws_instances" "vault_servers" {
  filter {
    name = "tag:aws:autoscaling:groupName"
    values = [aws_autoscaling_group.vault_cluster.name]
  }
}