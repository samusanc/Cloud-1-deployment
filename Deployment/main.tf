module "resource_group" {
    source = "./modules/resource_group"
    name = "cloud-1-rg-${terraform.workspace}"
    location =  var.location
}

module "virtual-network" {
    source = "./modules/virtual-network"
    name = "cloud-1-vn-${terraform.workspace}"
    address_space = var.address_space
    location = var.location
    resource_group_name = module.resource_group.name
}

module "subnet" {
    source = "./modules/subnet"
    virtual_network_name = module.virtual-network.name
    resource_group_name = module.resource_group.name
}

# Per-server resources below use count = var.vm_count, so a single apply
# provisions N independent servers in parallel. Names are indexed to stay
# unique within the resource group. The RG, VNet, subnet and NSG are shared.

module "public_ip" {
    source = "./modules/public_ip"
    count = var.vm_count
    name = "cloud-1-pip-${terraform.workspace}-${count.index}"
    location = var.location
    resource_group_name = module.resource_group.name
}

module "network_interface" {
    source = "./modules/network-interface"
    count = var.vm_count
    name = "cloud-1-nic-${terraform.workspace}-${count.index}"
    location = var.location
    resource_group_name = module.resource_group.name
    subnet_id = module.subnet.id
    public_ip_address_id =  module.public_ip[count.index].id
}

module "virtual_machine" {
    source = "./modules/virtual-machine"
    count = var.vm_count
    name = "cloud-1-vm-${terraform.workspace}-${count.index}"
    location = var.location
    resource_group_name = module.resource_group.name
    interface_id = module.network_interface[count.index].id
    env = var.env
    # Inject each VM's own public IP so cloud-init sets WP_URL=https://<ip>
    public_ip_address = module.public_ip[count.index].ip_address
}

module "NSG" {
    source = "./modules/NSG"
    location =  var.location
    resource_group_name = module.resource_group.name

}

module "NSG_Asociation" {
    source = "./modules/NSG_Asociation"
    count = var.vm_count
    network_interface_id = module.network_interface[count.index].id
    network_security_group_id = module.NSG.id

}