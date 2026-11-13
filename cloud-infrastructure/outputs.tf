output "tgw_id" {
  description = "ID of the Transit Gateway."
  value       = module.transit_gateway.tgw_id
}

output "hub_vpc_id" {
  description = "ID of the hub VPC."
  value       = module.vpc_hub.vpc_id
}

output "spoke_vpc_id" {
  description = "ID of the spoke VPC."
  value       = module.vpc_spoke.vpc_id
}

output "hub_attachment_id" {
  description = "ID of the hub Transit Gateway attachment."
  value       = aws_ec2_transit_gateway_vpc_attachment.hub_attachment.id
}

output "spoke_attachment_id" {
  description = "ID of the spoke Transit Gateway attachment."
  value       = aws_ec2_transit_gateway_vpc_attachment.spoke_attachment.id
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

output "spoke_vpc_cidr" {
  description = "CIDR block of the spoke VPC."
  value       = var.spoke_vpc_cidr
}

output "nat_enabled" {
  description = "Whether centralized egress through the hub NAT Gateway is enabled."
  value       = var.enable_nat_gateway
}

output "hub_public_route_table_id" {
  description = "ID of the hub public route table."
  value       = module.vpc_hub.public_route_table_id
}

output "spoke_private_route_table_id" {
  description = "ID of the spoke private route table."
  value       = module.vpc_spoke.private_route_table_id
}

output "hub_nat_public_ip" {
  description = "Public IP of the hub NAT Gateway (null when disabled)."
  value       = module.vpc_hub.nat_public_ip
}

output "spoke_test_instance_id" {
  description = "ID of the spoke test instance (null when not deployed)."
  value       = try(module.spoke_test_instance[0].instance_id, null)
}

output "flow_log_group_name" {
  description = "Name of the CloudWatch log group that receives the VPC flow logs."
  value       = module.flow_logs.log_group_name
}