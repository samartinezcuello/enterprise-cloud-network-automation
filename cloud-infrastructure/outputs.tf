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
