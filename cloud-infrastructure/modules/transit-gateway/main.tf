# AWS Transit Gateway (El núcleo de interconexión)
resource "aws_ec2_transit_gateway" "tgw" {
  description                     = "Transit Gateway central para Hub-and-Spoke"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"

  tags = {
    Name        = "tgw-${var.environment}"
    Environment = var.environment
  }
}