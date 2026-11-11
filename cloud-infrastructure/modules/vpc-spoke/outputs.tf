output "vpc_id" {
  description = "ID of the spoke VPC."
  value       = aws_vpc.spoke_vpc.id
}

output "private_subnet_id" {
  description = "ID of the spoke private subnet."
  value       = aws_subnet.private_subnet_1.id
}

output "private_route_table_id" {
  description = "ID of the spoke private route table (add Transit Gateway routes here)."
  value       = aws_route_table.private.id
}
