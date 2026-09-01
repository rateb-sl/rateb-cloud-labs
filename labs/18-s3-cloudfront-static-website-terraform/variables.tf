variable "aws_region" {
  description = "AWS Region for the S3 website origin."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Prefix used for the globally unique S3 bucket name."
  type        = string
  default     = "atlas-s3-cf"
}

variable "index_document" {
  description = "S3 website index document."
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "S3 website error document."
  type        = string
  default     = "error.html"
}
