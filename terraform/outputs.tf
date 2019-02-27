output "guardian_custom_dns" {
  value = "${module.guardian.guardian_custom_dns}"
}

output "guardian_direct_dns" {
  value = "${module.guardian.guardian_direct_dns}"
}

output "vault_server_ips" {
  value = "${module.guardian_vault.vault_server_public_ips}"
}

output "eximchain_node_lb_dns" {
  value = "${module.eximchain_node.eximchain_node_dns}"
}

output "eximchain_node_direct_dns" {
  value = "${module.eximchain_node.eximchain_node_ssh_dns}"
}
