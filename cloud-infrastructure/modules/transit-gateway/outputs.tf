output "tgw_id" {
  description = "ID del Transit Gateway creado"
  value       = aws_ec2_transit_gateway.tgw.id
}