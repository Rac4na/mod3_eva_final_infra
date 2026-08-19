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
