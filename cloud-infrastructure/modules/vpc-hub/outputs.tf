output "vpc_id" {
  description = "ID of the hub VPC."
  value       = aws_vpc.hub_vpc.id
}

output "public_subnet_id" {
  description = "ID of the hub public subnet."
  value       = aws_subnet.public_subnet_1.id
}

output "tgw_subnet_id" {
  description = "ID of the dedicated subnet for the Transit Gateway attachment."
  value       = aws_subnet.tgw_subnet.id
}

output "public_route_table_id" {
  description = "ID of the public route table (add spoke routes here)."
  value       = aws_route_table.public.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway (null when disabled)."
  value       = try(aws_nat_gateway.nat[0].id, null)
}
