variable "common_tags" {
  description = "description"
  type = map(string)
  default = {
    Project = "Islandora 8 Pilot"
  }
}

variable "route53_zone" {
  type = string
  default = "cloud.library.jhu.edu"
}

variable "project_prefix" {
  type = string
  default = "test"
}

variable "ssh_key_private" {
  type = string
  default = "~/.ssh/id_rsa"
}

variable "islandora_inv_path" {
  type = string
  default = "~/inventory"
}