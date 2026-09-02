# HashiCorp Get Started with Terraform on AWS, adapted for LocalStack.
# https://developer.hashicorp.com/terraform/tutorials/aws-get-started

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }

  required_version = ">= 1.2"
}

provider "aws" {
  region                      = "us-west-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  endpoints {
    ec2 = "http://localhost:4566"
  }
}

# LocalStack has no public Ubuntu AMI catalog. On real AWS, replace this
# variable with the tutorial's aws_ami data source and use its ID below.
variable "ami_id" {
  description = "AMI ID for the optional app_server resource"
  type        = string
  default     = "ami-0026a04369a3093cc"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.19.0"

  name = "example-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24"]

  enable_dns_hostnames = true
}

# Enable this block to practice managing an EC2 resource in the sandbox.
# The same resource is used to demonstrate create, update, and destroy.
/*
resource "aws_instance" "app_server" {
  ami           = var.ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = [module.vpc.default_security_group_id]
  subnet_id              = module.vpc.private_subnets[0]

  tags = {
    Name = var.instance_name
  }
}
*/
