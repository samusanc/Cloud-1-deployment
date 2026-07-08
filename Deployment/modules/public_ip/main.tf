resource "azurerm_public_ip" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  # Basic SKU public IPs were retired by Azure on 2025-09-30; Standard requires Static.
  sku               = "Standard"
  allocation_method = "Static"

  tags = {
    environment = "Production"
  }
}