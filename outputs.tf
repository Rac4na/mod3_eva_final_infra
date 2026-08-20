output "resource_group_name" {
  description = "Resource group creado."
  value       = azurerm_resource_group.this.name
}

output "container_app_fqdn" {
  description = "Dominio público asignado a la Container App."
  value       = azurerm_container_app.this.ingress[0].fqdn
}

output "app_url" {
  description = "URL base de la aplicación."
  value       = "https://${azurerm_container_app.this.ingress[0].fqdn}"
}

output "hello_endpoint" {
  description = "URL del endpoint /hello, lista para probar con curl."
  value       = "https://${azurerm_container_app.this.ingress[0].fqdn}/hello"
}

output "secreto_endpoint" {
  description = "URL del endpoint /secreto, que lee el valor desde el Key Vault."
  value       = "https://${azurerm_container_app.this.ingress[0].fqdn}/secreto"
}

output "key_vault_name" {
  description = "Key Vault que almacena el secreto."
  value       = azurerm_key_vault.this.name
}

output "app_identity_principal_id" {
  description = "Identidad con la que la app lee el secreto del Key Vault."
  value       = azurerm_user_assigned_identity.app.principal_id
}
