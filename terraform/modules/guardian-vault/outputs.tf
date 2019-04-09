output "vault_server_public_ips" {
  value = "${data.aws_instances.vault_servers.public_ips}"
}

output "vault_dns" {
  value = "${aws_route53_record.guardian.name}"
}

output "vault_port" {
  value = "${var.vault_port}"
}

output "vault_cert_bucket_name" {
  value = "${aws_s3_bucket.vault_certs.bucket}"
}

output "vault_cert_bucket_arn" {
  value = "${aws_s3_bucket.vault_certs.arn}"
}

output "vault_asg_name" {
  value = "${aws_autoscaling_group.vault_cluster.name}"
}

output "vault_cluster_size" {
  value = "${var.vault_cluster_size}"
}

output "vault_iam_role_id" {
  value = "${aws_iam_role.vault_cluster.id}"
}

output "vault_iam_role_arn" {
  value = "${aws_iam_role.vault_cluster.arn}"
}

output "vault_security_group_id" {
  value = "${aws_security_group.vault_cluster.id}"
}

output "vault_launch_config_name" {
  value = "${aws_launch_configuration.vault_cluster.name}"
}

output "vault_cluster_tag_key" {
  value = "Name"
}

output "vault_cluster_tag_value" {
  value = "guardian-vault"
}

output "consul_asg_name" {
  value = "${module.consul_cluster.asg_name}"
}

output "consul_cluster_size" {
  value = "${module.consul_cluster.cluster_size}"
}

output "consul_iam_role_id" {
  value = "${module.consul_cluster.iam_role_id}"
}

output "consul_iam_role_arn" {
  value = "${module.consul_cluster.iam_role_arn}"
}

output "consul_security_group_id" {
  value = "${module.consul_cluster.security_group_id}"
}

output "consul_launch_config_name" {
  value = "${module.consul_cluster.launch_config_name}"
}

output "consul_cluster_tag_key" {
  value = "${module.consul_cluster.cluster_tag_key}"
}

output "consul_cluster_tag_value" {
  value = "${module.consul_cluster.cluster_tag_value}"
}

output "vault_cert_s3_upload_id" {
  value = "${null_resource.vault_cert_s3_upload.id}"
}

output "vault_cert_access_policy_arn" {
  value = "${aws_iam_policy.vault_cert_access.arn}"
}
