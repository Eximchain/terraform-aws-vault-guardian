output "guardian_security_group" {
  value = "${aws_security_group.guardian.id}"
}

output "guardian_iam_role" {
  value = "${aws_iam_role.guardian.name}"
}

output "guardian_direct_dns" {
  value = "${aws_instance.guardian.public_dns}"
}

output "guardian_custom_dns" {
  value = "${aws_route53_record.guardian.*.name}"
}