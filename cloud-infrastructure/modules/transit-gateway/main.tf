# AWS Transit Gateway (central interconnection)
# Default route table association/propagation are disabled on purpose: every attachment is
# associated with, and propagates into, route tables that are declared explicitly (segmentation).
resource "aws_ec2_transit_gateway" "tgw" {
  description                     = "Central Transit Gateway for hub-and-spoke"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"

  tags = {
    Name        = "tgw-${var.environment}"
    Environment = var.environment
  }
}

# Route table of the spoke attachments: sees the hub (and the Internet through the hub), but not the other spokes.
resource "aws_ec2_transit_gateway_route_table" "spokes" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id

  tags = {
    Name = "tgw-rt-spokes-${var.environment}"
  }
}

# Route table of the hub attachment: sees every spoke (return traffic).
resource "aws_ec2_transit_gateway_route_table" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id

  tags = {
    Name = "tgw-rt-hub-${var.environment}"
  }
}