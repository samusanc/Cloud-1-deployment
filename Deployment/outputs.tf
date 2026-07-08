output "public_ip_addresses" {
  description = "Public IP of each deployed server."
  value       = module.public_ip[*].ip_address
}



