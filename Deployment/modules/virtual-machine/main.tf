resource "azurerm_linux_virtual_machine" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  custom_data = base64encode(templatefile("${path.root}/user-data", {
    env       = var.env
    public_ip = var.public_ip_address
  }))
  size                = "Standard_B2als_v2"
  admin_username      = "adminuser"
  network_interface_ids = [
    var.interface_id,
  ]

  admin_ssh_key {
    username = "adminuser"
    # Azure's admin_ssh_key requires an RSA key. Terraform's file() does NOT
    # expand "~", so pathexpand() is needed or the plan fails to find the file.
    public_key = file(pathexpand("~/.ssh/id_rsa.pub"))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}