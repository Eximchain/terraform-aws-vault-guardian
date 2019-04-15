# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN AUTO SCALING GROUP (ASG) TO RUN VAULT
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_autoscaling_group" "vault_cluster" {
  launch_configuration = "${aws_launch_configuration.vault_cluster.name}"

  vpc_zone_identifier = ["${aws_subnet.vault.*.id}"]

  # Use a fixed-size cluster
  min_size             = "${var.vault_cluster_size}"
  max_size             = "${var.vault_cluster_size}"
  desired_capacity     = "${var.vault_cluster_size}"
  termination_policies = ["Default"]

  target_group_arns         = ["${aws_lb_target_group.guardian_vault.arn}"]
  health_check_type         = "EC2"
  health_check_grace_period = 300
  wait_for_capacity_timeout = "10m"

  tags = [
    {
      key                 = "Name"
      value               = "guardian-vault"
      propagate_at_launch = true
    },{
      key                 = "Purpose"
      value               = "TxExecutorVault"
      propagate_at_launch = true
    },{
      key                 = "Region"
      value               = "${var.aws_region}"
      propagate_at_launch = true
    },
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE LAUNCH CONFIGURATION TO DEFINE WHAT RUNS ON EACH INSTANCE IN THE ASG
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_launch_configuration" "vault_cluster" {
  name_prefix   = "guardian-vault-"
  image_id      = "${var.vault_consul_ami == "" ? element(coalescelist(data.aws_ami.vault_consul.*.id, list("")), 0) : var.vault_consul_ami}"
  instance_type = "${var.vault_instance_type}"
  user_data     = "${data.template_file.user_data_vault_cluster.rendered}"

  iam_instance_profile        = "${aws_iam_instance_profile.vault_cluster.name}"
  key_name                    = "${aws_key_pair.auth.id}"
  security_groups             = ["${aws_security_group.vault_cluster.id}"]
  placement_tenancy           = "default"
  associate_public_ip_address = true

  ebs_optimized = false

  root_block_device {
    volume_type           = "standard"
    volume_size           = 50
    delete_on_termination = true
  }

  # Important note: whenever using a launch configuration with an auto scaling group, you must set
  # create_before_destroy = true. However, as soon as you set create_before_destroy = true in one resource, you must
  # also set it in every resource that it depends on, or you'll get an error about cyclic dependencies (especially when
  # removing resources). For more info, see:
  #
  # https://www.terraform.io/docs/providers/aws/r/launch_configuration.html
  # https://terraform.io/docs/configuration/resources.html
  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A SECURITY GROUP TO CONTROL WHAT REQUESTS CAN GO IN AND OUT OF EACH EC2 INSTANCE
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group" "vault_cluster" {
  name_prefix = "guardian-vault-"
  description = "Security group for the guardian-vault launch configuration"
  vpc_id      = "${var.aws_vpc}"

  # aws_launch_configuration.launch_configuration in this module sets create_before_destroy to true, which means
  # everything it depends on, including this resource, must set it as well, or you'll get cyclic dependency errors
  # when you try to do a terraform destroy.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "allow_ssh_inbound_from_cidr_blocks" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.vault_cluster.id}"
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.vault_cluster.id}"
}

# ---------------------------------------------------------------------------------------------------------------------
# VAULT RULES
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group_rule" "allow_api_inbound_from_cidr_blocks" {
  type        = "ingress"
  from_port   = 8200
  to_port     = 8200
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.vault_cluster.id}"
}

resource "aws_security_group_rule" "allow_cluster_inbound_from_self" {
  type      = "ingress"
  from_port = 8201
  to_port   = 8201
  protocol  = "tcp"
  self      = true

  security_group_id = "${aws_security_group.vault_cluster.id}"
}

# ---------------------------------------------------------------------------------------------------------------------
# ATTACH AN IAM ROLE TO EACH EC2 INSTANCE
# We can use the IAM role to grant the instance IAM permissions so we can use the AWS APIs without having to figure out
# how to get our secret AWS access keys onto the box.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_instance_profile" "vault_cluster" {
  name_prefix = "guardian-vault-"
  path        = "/"
  role        = "${aws_iam_role.vault_cluster.name}"

  # aws_launch_configuration.launch_configuration in this module sets create_before_destroy to true, which means
  # everything it depends on, including this resource, must set it as well, or you'll get cyclic dependency errors
  # when you try to do a terraform destroy.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "vault_cluster" {
  name_prefix        = "guardian-vault-"
  assume_role_policy = "${data.aws_iam_policy_document.vault_cluster.json}"

  # aws_iam_instance_profile.instance_profile in this module sets create_before_destroy to true, which means
  # everything it depends on, including this resource, must set it as well, or you'll get cyclic dependency errors
  # when you try to do a terraform destroy.
  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "vault_cluster" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN S3 BUCKET TO USE AS A STORAGE BACKEND
# Also, add an IAM role policy that gives the Vault servers access to this S3 bucket
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "guardian_vault" {
  bucket_prefix = "guardian-vault-"
  force_destroy = "${var.force_destroy_s3_bucket}"
}

resource "aws_iam_role_policy" "vault_s3" {
  name   = "vault_s3"
  role   = "${aws_iam_role.vault_cluster.id}"
  policy = "${data.aws_iam_policy_document.vault_s3.json}"
}

data "aws_iam_policy_document" "vault_s3" {
  statement {
    effect  = "Allow"
    actions = ["s3:*"]

    resources = [
      "${aws_s3_bucket.guardian_vault.arn}",
      "${aws_s3_bucket.guardian_vault.arn}/*",
    ]
  }
}
