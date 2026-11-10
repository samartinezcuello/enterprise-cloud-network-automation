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

# 1. Módulo VPC Hub (Central con salida a Internet)
module "vpc_hub" {
  source      = "./modules/vpc-hub"
  vpc_cidr    = "10.0.0.0/16"
  environment = "production"
}

# 2. Módulo Transit Gateway (El router central)
module "transit_gateway" {
  source      = "./modules/transit-gateway"
  environment = "production"
}

# 3. Módulo VPC Spoke (Cargas de trabajo aisladas)
module "vpc_spoke" {
  source      = "./modules/vpc-spoke"
  vpc_cidr    = "10.1.0.0/16"
  environment = "production"
}

# 4. Adjuntar la VPC Hub al Transit Gateway
resource "aws_ec2_transit_gateway_vpc_attachment" "hub_attachment" {
  transit_gateway_id = module.transit_gateway.tgw_id
  vpc_id             = module.vpc_hub.vpc_id
  subnet_ids         = [module.vpc_hub.public_subnet_id] # En producción idealmente subnet dedicada, aquí usamos la pública de base

  tags = {
    Name = "tgw-attachment-hub"
  }
}

# 5. Adjuntar la VPC Spoke al Transit Gateway
resource "aws_ec2_transit_gateway_vpc_attachment" "spoke_attachment" {
  transit_gateway_id = module.transit_gateway.tgw_id
  vpc_id             = module.vpc_spoke.vpc_id
  subnet_ids         = [module.vpc_spoke.private_subnet_id]

  tags = {
    Name = "tgw-attachment-spoke"
  }
}