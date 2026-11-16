output "tgw_id" {
  description = "ID of the Transit Gateway."
  value       = aws_ec2_transit_gateway.tgw.id
}

output "spokes_route_table_id" {
  description = "ID of the Transit Gateway route table associated with the spoke attachments."
  value       = aws_ec2_transit_gateway_route_table.spokes.id
}

output "hub_route_table_id" {
  description = "ID of the Transit Gateway route table associated with the hub attachment."
  value       = aws_ec2_transit_gateway_route_table.hub.id
}
