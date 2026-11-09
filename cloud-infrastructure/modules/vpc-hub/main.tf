# VPC Central (Hub)
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

# Subnet Pública (para Internet Gateway)
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.hub_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, 0) # 10.0.0.0/20
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-hub-public-us-east-1a"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.hub_vpc.id

  tags = {
    Name = "igw-hub-${var.environment}"
  }
}