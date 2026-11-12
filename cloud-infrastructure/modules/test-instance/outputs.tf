output "instance_id" {
  description = "ID of the test instance."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP address of the test instance."
  value       = aws_instance.this.private_ip
}