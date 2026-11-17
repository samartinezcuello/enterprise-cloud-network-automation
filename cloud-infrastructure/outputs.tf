output "tgw_id" {
  description = "ID of the Transit Gateway."
  value       = module.transit_gateway.tgw_id
}

output "hub_vpc_id" {
  description = "ID of the hub VPC."
  value       = module.vpc_hub.vpc_id
}

output "hub_attachment_id" {
  description = "ID of the hub Transit Gateway attachment."
  value       = aws_ec2_transit_gateway_vpc_attachment.hub_attachment.id
}


# ---------------------------------------------------------------------------
# Test-Script Input
# ---------------------------------------------------------------------------
output "region" {
  description = "AWS region used by the lab."
  value       = var.region
}

output "hub_vpc_cidr" {
  description = "CIDR block of the hub VPC."
  value       = var.hub_vpc_cidr
}

output "nat_enabled" {
  description = "Whether centralized egress through the hub NAT Gateway is enabled."
  value       = var.enable_nat_gateway
}

output "hub_public_route_table_id" {
  description = "ID of the hub public route table."
  value       = module.vpc_hub.public_route_table_id
}

output "hub_nat_public_ip" {
  description = "Public IP of the hub NAT Gateway (null when disabled)."
  value       = module.vpc_hub.nat_public_ip
}

output "flow_log_group_name" {
  description = "Name of the CloudWatch log group that receives the VPC flow logs."
  value       = module.flow_logs.log_group_name
}


output "tgw_hub_route_table_id" {
  description = "ID of the Transit Gateway route table associated with the hub attachment."
  value       = module.transit_gateway.hub_route_table_id
}

output "tgw_spokes_route_table_id" {
  description = "ID of the Transit Gateway route table associated with the spoke attachments."
  value       = module.transit_gateway.spokes_route_table_id
}

output "allow_spoke_to_spoke" {
  description = "Whether traffic between spokes is allowed through the Transit Gateway."
  value       = var.allow_spoke_to_spoke
}

output "spokes" {
  description = "Per-spoke data (VPC, CIDR, attachment, route table and test instance) used by the verification script."

  value = {
    for key, spoke in module.vpc_spoke : key => {
      vpc_id                 = spoke.vpc_id
      cidr                   = var.spokes[key].cidr
      attachment_id          = aws_ec2_transit_gateway_vpc_attachment.spoke_attachment[key].id
      private_route_table_id = spoke.private_route_table_id
      test_instance_id       = try(module.spoke_test_instance[key].instance_id, null)
      test_instance_ip       = try(module.spoke_test_instance[key].private_ip, null)
    }
  }
}