output "vpc_id" {
  description = "ID de la VPC Spoke creada"
  value       = aws_vpc.spoke_vpc.id
}

output "private_subnet_id" {
  description = "ID de la Subnet Privada de la VPC Spoke"
  value       = aws_subnet.private_subnet_1.id
}