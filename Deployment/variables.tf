
variable "location" {
    type = string
}

variable "vm_count" {
    type        = number
    default     = 1
    description = "How many WordPress servers to deploy in parallel."
}

variable "env" {
  type = string
}

variable "tags" {
    type = map(string)

    default = {
      "project" = "cloud-1"
    }
  
}


variable "address_space" {
    type = list(string)
}