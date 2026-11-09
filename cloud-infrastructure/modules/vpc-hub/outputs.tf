output "vpc_id" {
  description = "ID de la VPC Hub creada"
  value       = aws_vpc.hub_vpc.id
}

output "public_subnet_id" {
  description = "ID de la Subnet Publica de la VPC Hub"
  value       = aws_subnet.public_subnet_1.id
}