# AWS Transit Gateway (central interconnection)
resource "aws_ec2_transit_gateway" "tgw" {
  description                     = "Central Transit Gateway for hub-and-spoke"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"

  tags = {
    Name        = "tgw-${var.environment}"
    Environment = var.environment
  }
}
