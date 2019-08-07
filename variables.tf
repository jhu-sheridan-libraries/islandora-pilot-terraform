variable "vpc_id" {
    type = string
}

variable "common_tags" {
  description = "description"
  type = map(string)
  default = {
          Project = "Islandora 8 Pilot"
      }
}
