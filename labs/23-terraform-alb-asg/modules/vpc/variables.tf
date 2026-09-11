variable "project_name" {
  description = "Name used for VPC resource names and tags"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR range for the VPC"
  type        = string
}
