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
module "guardian" {
  # Source from github if using in another project
  source = "modules/guardian-app"

  # Ensure the VPC Route is preserved for certificate revocation during instance destroy
  aws_route = "${aws_route.guardian.id}"

  # Variables sourced from terraform.tfvars
  public_key                     = "${var.public_key == "" ? join("", data.local_file.public_key.*.content) : var.public_key}"
  private_key                    = "${var.private_key}"
  aws_region                     = "${var.aws_region}"
  availability_zone              = "${var.availability_zone}"
  cert_owner                     = "${var.cert_owner}"
  force_destroy_s3_buckets       = "${var.force_destroy_s3_buckets}"
  guardian_instance_type         = "${var.guardian_instance_type}"
  guardian_api_cidrs             = "${var.guardian_api_cidrs}"
  guardian_api_security_groups   = "${var.guardian_api_security_groups}"

  # Variables sourced from the vault module
  vault_dns                = "${module.guardian_vault.vault_dns}"
  vault_cert_s3_upload_id  = "${module.guardian_vault.vault_cert_s3_upload_id}"
  vault_cert_bucket_name   = "${module.guardian_vault.vault_cert_bucket_name}"
  vault_cert_bucket_arn    = "${module.guardian_vault.vault_cert_bucket_arn}"
  consul_cluster_tag_key   = "${module.guardian_vault.consul_cluster_tag_key}"
  consul_cluster_tag_value = "${module.guardian_vault.consul_cluster_tag_value}"

  aws_vpc = "${aws_vpc.guardian.id}"

  base_subnet_cidr = "${cidrsubnet(var.vpc_cidr, 2, 0)}"

  guardian_ami = "${var.guardian_ami}"

  subdomain_name = "${var.subdomain_name}"
  root_domain    = "${var.root_domain}"
}

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
}
