output "backend_config" {
  description = "Values used to initialise the 10-governance and 20-platform azurerm backends."
  value = {
    resource_group_name  = azurerm_resource_group.state.name
    storage_account_name = azurerm_storage_account.state.name
    container_name       = azurerm_storage_container.state.name
    use_azuread_auth     = true
  }
}

output "state_resource_group_name" {
  value = azurerm_resource_group.state.name
}

output "state_storage_account_name" {
  value = azurerm_storage_account.state.name
}

output "state_container_name" {
  value = azurerm_storage_container.state.name
}

output "backend_init_examples" {
  description = "Run from the relevant Terraform root; give each root a different key."
  value = {
    governance = "terraform init -backend-config=resource_group_name=${azurerm_resource_group.state.name} -backend-config=storage_account_name=${azurerm_storage_account.state.name} -backend-config=container_name=${azurerm_storage_container.state.name} -backend-config=key=10-governance.tfstate -backend-config=use_azuread_auth=true"
    platform   = "terraform init -backend-config=resource_group_name=${azurerm_resource_group.state.name} -backend-config=storage_account_name=${azurerm_storage_account.state.name} -backend-config=container_name=${azurerm_storage_container.state.name} -backend-config=key=20-platform.tfstate -backend-config=use_azuread_auth=true"
  }
}
