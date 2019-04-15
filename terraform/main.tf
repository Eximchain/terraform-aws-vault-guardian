provider "aws" {
  version = "~> 1.5"

  region = "${var.aws_region}"
}

provider "local" {
  version = "~> 1.1"
}

# ---------------------------------------------------------------------------------------------------------------------
# NETWORKING
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_vpc" "guardian" {
  cidr_block           = "${var.vpc_cidr}"
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "guardian" {
  vpc_id = "${aws_vpc.guardian.id}"
}

resource "aws_route" "guardian" {
  route_table_id         = "${aws_vpc.guardian.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.guardian.id}"
}

# ---------------------------------------------------------------------------------------------------------------------
# PUBLIC KEY FILE IF USED
# ---------------------------------------------------------------------------------------------------------------------
data "local_file" "public_key" {
  count = "${var.public_key == "" ? 1 : 0}"

  filename = "${var.public_key_path}"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULES
# ---------------------------------------------------------------------------------------------------------------------
module "guardian_vault" {
  source = "modules/guardian-vault"

  vault_consul_ami = "${var.vault_consul_ami}"
  cert_owner       = "${var.cert_owner}"
  public_key       = "${var.public_key == "" ? join("", data.local_file.public_key.*.content) : var.public_key}"

  aws_region    = "${var.aws_region}"
  vault_port    = "${var.vault_port}"
  cert_org_name = "${var.cert_org_name}"

  okta_api_token = "${var.okta_api_token}"

  force_destroy_s3_bucket = "${var.force_destroy_s3_buckets}"

  aws_vpc = "${aws_vpc.guardian.id}"

  base_subnet_cidr = "${cidrsubnet(var.vpc_cidr, 2, 1)}"

  vault_log_level = "${var.vault_log_level}"

  vault_cluster_size   = "${var.vault_cluster_size}"
  vault_instance_type  = "${var.vault_instance_type}"
  consul_cluster_size  = "${var.consul_cluster_size}"
  consul_instance_type = "${var.consul_instance_type}"

  subdomain_name = "${var.subdomain_name}"
  root_domain    = "${var.root_domain}"

  letsencrypt_webmaster   = "${var.letsencrypt_webmaster}"
  letsencrypt_acme_server = "${var.letsencrypt_acme_server}"
}
