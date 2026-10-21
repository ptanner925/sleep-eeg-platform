output "resource_group_name" {
  description = "Name of the ephemeral dev resource group (destroyed by make down)."
  value       = azurerm_resource_group.this.name
}
