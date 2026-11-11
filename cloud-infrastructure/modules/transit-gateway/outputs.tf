output "tgw_id" {
  description = "ID of the Transit Gateway."
  value       = aws_ec2_transit_gateway.tgw.id
}

output "default_route_table_id" {
  description = "ID of the Transit Gateway default route table."
  value       = aws_ec2_transit_gateway.tgw.association_default_route_table_id
}
