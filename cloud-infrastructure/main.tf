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

locals {
  # Pinned availability zone: avoids relying on the ordering of a data source result,
  # which could change and force subnet recreation if AWS adds a zone.
  az = "${var.region}${var.az_suffix}"
}

# 0. Flow logs infrastructure: KMS key, log group and IAM role shared by both VPCs
module "flow_logs" {
  source = "./modules/flow-logs"

  name        = "hub-spoke-${var.environment}"
  environment = var.environment
}

# 1. Hub VPC: central network with internet egress
module "vpc_hub" {
  source = "./modules/vpc-hub"

  vpc_cidr                 = var.hub_vpc_cidr
  environment              = var.environment
  availability_zone        = local.az
  enable_nat_gateway       = var.enable_nat_gateway
  flow_log_destination_arn = module.flow_logs.log_group_arn
  flow_log_role_arn        = module.flow_logs.role_arn
  flow_log_format          = module.flow_logs.log_format
}

# 2. Transit Gateway: central router
module "transit_gateway" {
  source = "./modules/transit-gateway"

  environment = var.environment
}

# 3. Spoke VPC: isolated workloads
module "vpc_spoke" {
  source   = "./modules/vpc-spoke"
  for_each = var.spokes

  spoke_name               = each.key
  vpc_cidr                 = each.value.cidr
  environment              = var.environment
  availability_zone        = local.az
  flow_log_destination_arn = module.flow_logs.log_group_arn
  flow_log_role_arn        = module.flow_logs.role_arn
  flow_log_format          = module.flow_logs.log_format
}

# 4. Hub attachment (dedicated /28 subnet)
resource "aws_ec2_transit_gateway_vpc_attachment" "hub_attachment" {
  transit_gateway_id = module.transit_gateway.tgw_id
  vpc_id             = module.vpc_hub.vpc_id
  subnet_ids         = [module.vpc_hub.tgw_subnet_id]

  # Associations and propagations are managed explicitly below
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = {
    Name = "tgw-attachment-hub-${var.environment}"
  }
}

# 5. Spoke attachments (one per spoke)
resource "aws_ec2_transit_gateway_vpc_attachment" "spoke_attachment" {
  for_each = var.spokes

  transit_gateway_id = module.transit_gateway.tgw_id
  vpc_id             = module.vpc_spoke[each.key].vpc_id
  subnet_ids         = [module.vpc_spoke[each.key].private_subnet_id]

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = {
    Name = "tgw-attachment-spoke-${each.key}-${var.environment}"
  }
}


# ---------------------------------------------------------------------------
# Transit Gateway segmentation
#   - spokes route table: associated with the spoke attachments. It learns the hub CIDR
#     (and the default route to the Internet), but NOT the other spokes.
#   - hub route table: associated with the hub attachment. It learns every spoke CIDR.
# ---------------------------------------------------------------------------

# Associations: each attachment belongs to exactly one TGW route table
resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub_attachment.id
  transit_gateway_route_table_id = module.transit_gateway.hub_route_table_id
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each = var.spokes

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke_attachment[each.key].id
  transit_gateway_route_table_id = module.transit_gateway.spokes_route_table_id
}

# Propagations: which attachment announces its CIDR into which route table
resource "aws_ec2_transit_gateway_route_table_propagation" "hub_into_spokes" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub_attachment.id
  transit_gateway_route_table_id = module.transit_gateway.spokes_route_table_id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "spoke_into_hub" {
  for_each = var.spokes

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke_attachment[each.key].id
  transit_gateway_route_table_id = module.transit_gateway.hub_route_table_id
}

# Spoke-to-spoke traffic: blocked by default, opt-in with allow_spoke_to_spoke = true.
# Blocked: a blackhole route per spoke CIDR in the spokes route table. It is more specific
# than the default route to the hub, so inter-spoke traffic is dropped at the Transit Gateway.
resource "aws_ec2_transit_gateway_route" "spoke_blackhole" {
  for_each = var.allow_spoke_to_spoke ? {} : var.spokes

  destination_cidr_block         = each.value.cidr
  blackhole                      = true
  transit_gateway_route_table_id = module.transit_gateway.spokes_route_table_id
}

# Allowed: every spoke also propagates into the spokes route table.
resource "aws_ec2_transit_gateway_route_table_propagation" "spoke_into_spokes" {
  for_each = var.allow_spoke_to_spoke ? var.spokes : {}

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke_attachment[each.key].id
  transit_gateway_route_table_id = module.transit_gateway.hub_route_table_id
}

# ---------------------------------------------------------------------------
# VPC routing (without these routes the attachments exist but no traffic flows)
# ---------------------------------------------------------------------------

# Spoke -> Hub
resource "aws_route" "spoke_to_hub" {
  for_each = var.spokes

  route_table_id         = module.vpc_spoke[each.key].private_route_table_id
  destination_cidr_block = var.hub_vpc_cidr
  transit_gateway_id     = module.transit_gateway.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke_attachment]
}

# Hub -> Spoke (also the return path for traffic NATed by the hub)
resource "aws_route" "hub_public_to_spoke" {
  for_each = var.spokes

  route_table_id         = module.vpc_hub.public_route_table_id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = module.transit_gateway.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.hub_attachment]
}

# ---------------------------------------------------------------------------
# Centralized egress: spoke -> TGW -> hub NAT Gateway -> Internet
# Only active when enable_nat_gateway = true (the NAT Gateway is billed per hour)
# ---------------------------------------------------------------------------
resource "aws_route" "spoke_default_to_tgw" {
  for_each = var.enable_nat_gateway ? var.spokes : {}

  route_table_id         = module.vpc_spoke[each.key].private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = module.transit_gateway.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke_attachment]
}

resource "aws_ec2_transit_gateway_route" "default_to_hub" {
  count = var.enable_nat_gateway ? 1 : 0

  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub_attachment.id
  transit_gateway_route_table_id = module.transit_gateway.spokes_route_table_id
}

# ---------------------------------------------------------------------------
# Optional test workload, one per spoke (no public IP, no SSH: access via SSM)
# SSM is reached through the centralized egress path (spoke -> TGW -> hub NAT)
# ---------------------------------------------------------------------------
module "spoke_test_instance" {
  source   = "./modules/test-instance"
  for_each = var.deploy_test_instance ? var.spokes : {}

  name            = "spoke-${each.key}-test-${var.environment}"
  environment     = var.environment
  vpc_id          = module.vpc_spoke[each.key].vpc_id
  subnet_id       = module.vpc_spoke[each.key].private_subnet_id
  icmp_peer_cidrs = [for spoke in var.spokes : spoke.cidr]

  depends_on = [aws_route.spoke_default_to_tgw]
}

check "test_instance_needs_egress" {
  assert {
    condition     = !var.deploy_test_instance || var.enable_nat_gateway
    error_message = "The test instance reaches SSM through the hub NAT Gateway: set enable_nat_gateway = true."
  }
}