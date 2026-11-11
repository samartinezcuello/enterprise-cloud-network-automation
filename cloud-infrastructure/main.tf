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
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az = data.aws_availability_zones.available.names[0]
}

# 1. Hub VPC: central network with internet egress
module "vpc_hub" {
  source = "./modules/vpc-hub"

  vpc_cidr           = var.hub_vpc_cidr
  environment        = var.environment
  availability_zone  = local.az
  enable_nat_gateway = var.enable_nat_gateway
}

# 2. Transit Gateway: central router
module "transit_gateway" {
  source = "./modules/transit-gateway"

  environment = var.environment
}

# 3. Spoke VPC: isolated workloads
module "vpc_spoke" {
  source = "./modules/vpc-spoke"

  vpc_cidr          = var.spoke_vpc_cidr
  environment       = var.environment
  availability_zone = local.az
}

# 4. Hub attachment (dedicated /28 subnet)
resource "aws_ec2_transit_gateway_vpc_attachment" "hub_attachment" {
  transit_gateway_id = module.transit_gateway.tgw_id
  vpc_id             = module.vpc_hub.vpc_id
  subnet_ids         = [module.vpc_hub.tgw_subnet_id]

  tags = {
    Name = "tgw-attachment-hub-${var.environment}"
  }
}

# 5. Spoke attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "spoke_attachment" {
  transit_gateway_id = module.transit_gateway.tgw_id
  vpc_id             = module.vpc_spoke.vpc_id
  subnet_ids         = [module.vpc_spoke.private_subnet_id]

  tags = {
    Name = "tgw-attachment-spoke-${var.environment}"
  }
}

# ---------------------------------------------------------------------------
# VPC routing (without these routes the attachments exist but no traffic flows)
# ---------------------------------------------------------------------------

# Spoke -> Hub
resource "aws_route" "spoke_to_hub" {
  route_table_id         = module.vpc_spoke.private_route_table_id
  destination_cidr_block = var.hub_vpc_cidr
  transit_gateway_id     = module.transit_gateway.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke_attachment]
}

# Hub -> Spoke (also the return path for traffic NATed by the hub)
resource "aws_route" "hub_public_to_spoke" {
  route_table_id         = module.vpc_hub.public_route_table_id
  destination_cidr_block = var.spoke_vpc_cidr
  transit_gateway_id     = module.transit_gateway.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.hub_attachment]
}

# ---------------------------------------------------------------------------
# Centralized egress: spoke -> TGW -> hub NAT Gateway -> Internet
# Only active when enable_nat_gateway = true (the NAT Gateway is billed per hour)
# ---------------------------------------------------------------------------
resource "aws_route" "spoke_default_to_tgw" {
  count = var.enable_nat_gateway ? 1 : 0

  route_table_id         = module.vpc_spoke.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = module.transit_gateway.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke_attachment]
}

resource "aws_ec2_transit_gateway_route" "default_to_hub" {
  count = var.enable_nat_gateway ? 1 : 0

  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub_attachment.id
  transit_gateway_route_table_id = module.transit_gateway.default_route_table_id
}
