output "guardian_custom_dns" {
  value = "${module.guardian_vault.vault_dns}"
}

output "vault_server_ips" {
  value = "${module.guardian_vault.vault_server_public_ips}"
}
