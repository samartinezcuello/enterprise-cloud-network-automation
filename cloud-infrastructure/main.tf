terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "vpc_hub" {
  source      = "./modules/vpc-hub"
  vpc_cidr    = "10.0.0.0/16"
  environment = "production"
}