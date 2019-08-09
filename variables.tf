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