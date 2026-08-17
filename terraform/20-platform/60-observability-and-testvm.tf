###############################################################################
# Management landing zone - Log Analytics
#
# In ALZ this lives in the "Management" platform subscription and every other
# subscription streams into it. One workspace, one query surface.
#
# GCP mental model: this is your Cloud Logging log sink destination plus the
# metrics backend, rolled into one - and KQL is the query language instead of
# Logs Explorer's filter syntax.
###############################################################################

resource "azurerm_resource_group" "management" {
  provider = azurerm

  name     = "rg-${var.prefix}-management-${var.location}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_log_analytics_workspace" "platform" {
  provider = azurerm

  name                = "log-${var.prefix}-platform-${var.location}"
  resource_group_name = azurerm_resource_group.management.name
  location            = azurerm_resource_group.management.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  # Lab guard rail: without a cap, one chatty diagnostic setting can eat a
  # month of credit overnight.
  daily_quota_gb = 1

  tags = var.tags
}

###############################################################################
# Test VM  (COST TOGGLE: var.enable_test_vm)
#
# Deliberately has NO public IP and NO Bastion. You drive it with:
#
#   az vm run-command invoke -g <rg> -n <vm> \
#     --command-id RunShellScript --scripts "nslookup <storage>.blob.core.windows.net"
#
# run-command goes through the Azure control plane and the VM agent, not the
# data plane, so it works on a fully private VM and avoids deploying Bastion
# solely for this DNS exercise.
###############################################################################

resource "random_password" "vm" {
  count = var.enable_test_vm ? 1 : 0

  length           = 24
  special          = true
  override_special = "!#%*-_"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
}

resource "azurerm_network_interface" "test_vm" {
  provider = azurerm.corp_dev

  count = var.enable_test_vm ? 1 : 0

  name                = "nic-${var.prefix}-testvm"
  resource_group_name = azurerm_resource_group.landing_zone.name
  location            = azurerm_resource_group.landing_zone.location
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.workload.id
    private_ip_address_allocation = "Dynamic"
    # No public_ip_address_id - which is also what the custom "no public IP on
    # NIC" policy in 10-governance is there to enforce.
  }
}

resource "azurerm_linux_virtual_machine" "test" {
  provider = azurerm.corp_dev

  count = var.enable_test_vm ? 1 : 0

  name                = "vm-${var.prefix}-test"
  resource_group_name = azurerm_resource_group.landing_zone.name
  location            = azurerm_resource_group.landing_zone.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  admin_password      = random_password.vm[0].result
  tags                = var.tags

  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.test_vm[0].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}
