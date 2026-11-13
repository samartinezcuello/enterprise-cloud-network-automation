# Hub VPC (central transit network)
resource "aws_vpc" "hub_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "vpc-hub-${var.environment}"
    Environment = var.environment
    Role        = "Transit Hub"
  }
}

# Lock down the default security group: no rules means no traffic
resource "aws_default_security_group" "hub_default" {
  vpc_id = aws_vpc.hub_vpc.id

  tags = {
    Name = "sg-hub-default-locked-${var.environment}"
  }
}

# Public subnet (hosts the NAT Gateway)
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.hub_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, 0) # 10.0.0.0/20
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-hub-public-${var.availability_zone}"
  }
}

# Dedicated /28 subnet for the Transit Gateway attachment (last /28 of the VPC)
resource "aws_subnet" "tgw_subnet" {
  vpc_id                  = aws_vpc.hub_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 12, 4095) # 10.0.255.240/28
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-hub-tgw-${var.availability_zone}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.hub_vpc.id

  tags = {
    Name = "igw-hub-${var.environment}"
  }
}

# Public route table: internet via IGW (spoke routes are added from the root module)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.hub_vpc.id

  tags = {
    Name = "rt-hub-public-${var.environment}"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public.id
}

# TGW attachment subnet route table: default route to NAT when egress is enabled
resource "aws_route_table" "tgw" {
  vpc_id = aws_vpc.hub_vpc.id

  tags = {
    Name = "rt-hub-tgw-${var.environment}"
  }
}

resource "aws_route_table_association" "tgw" {
  subnet_id      = aws_subnet.tgw_subnet.id
  route_table_id = aws_route_table.tgw.id
}

# Optional NAT Gateway (single, cost-aware)
resource "aws_eip" "nat" {
  # checkov:skip=CKV2_AWS_19: The EIP is consumed by the NAT Gateway, not by an EC2 instance
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "eip-hub-nat-${var.environment}"
  }
}

resource "aws_nat_gateway" "nat" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public_subnet_1.id

  tags = {
    Name = "nat-hub-${var.environment}"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route" "tgw_subnet_default_to_nat" {
  count = var.enable_nat_gateway ? 1 : 0

  route_table_id         = aws_route_table.tgw.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[0].id
}


# VPC Flow Logs: all traffic (accepted and rejected) to CloudWatch Logs
resource "aws_flow_log" "hub" {
  vpc_id                   = aws_vpc.hub_vpc.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = var.flow_log_destination_arn
  iam_role_arn             = var.flow_log_role_arn
  log_format               = var.flow_log_format
  max_aggregation_interval = 60

  tags = {
    Name = "flow-log-hub-${var.environment}"
  }
}