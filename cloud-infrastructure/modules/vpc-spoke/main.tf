# Spoke VPC (isolated workloads)
resource "aws_vpc" "spoke_vpc" {
  # checkov:skip=CKV2_AWS_11: VPC Flow Logs pending, planned for the observability phase
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "vpc-spoke-${var.environment}"
    Environment = var.environment
    Role        = "Workload Spoke"
  }
}

# Lock down the default security group: no rules means no traffic
resource "aws_default_security_group" "spoke_default" {
  vpc_id = aws_vpc.spoke_vpc.id

  tags = {
    Name = "sg-spoke-default-locked-${var.environment}"
  }
}

# Private subnet for workloads (no direct internet gateway: everything goes through the TGW)
resource "aws_subnet" "private_subnet_1" {
  vpc_id                  = aws_vpc.spoke_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, 0) # 10.1.0.0/20
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-spoke-private-${var.availability_zone}"
  }
}

# Private route table: routes to the hub are added from the root module
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.spoke_vpc.id

  tags = {
    Name = "rt-spoke-private-${var.environment}"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private.id
}
