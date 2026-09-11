variable "project_name" {
  description = "Name used for compute resource names and tags"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where compute resources are placed"
  type        = string
}

variable "subnet_ids" {
  description = "Public subnet IDs used by the ALB and Auto Scaling Group"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID attached to the ALB"
  type        = string
}

variable "web_security_group_id" {
  description = "Security group ID attached to web instances"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for web servers"
  type        = string
  default     = "t3.micro"

  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium"], var.instance_type)
    error_message = "instance_type must be t3.micro, t3.small, or t3.medium."
  }
}

variable "enable_access_logs" {
  description = "Whether to enable ALB access logging"
  type        = bool
  default     = false
}

variable "access_logs_bucket" {
  description = "S3 bucket used for ALB access logs"
  type        = string
  default     = ""
}
