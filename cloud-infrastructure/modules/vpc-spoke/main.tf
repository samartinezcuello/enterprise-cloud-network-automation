# VPC Spoke (Cargas de trabajo / Aplicaciones)
resource "aws_vpc" "spoke_vpc" {
  # checkov:skip=CKV2_AWS_11: Flow logs omitidos para entorno de pruebas de laboratorio
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "vpc-spoke-${var.environment}"
    Environment = var.environment
    Role        = "Workload Spoke"
  }
}

# Subnet Privada para las cargas de trabajo (sin salida directa a IGW, todo sale por TGW)
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.spoke_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, 0) # Ej: 10.1.0.0/20 si el CIDR es 10.1.0.0/16
  availability_zone = "us-east-1a"

  tags = {
    Name = "subnet-spoke-private-us-east-1a"
  }
}

resource "aws_default_security_group" "spoke_default" {
  vpc_id = aws_vpc.spoke_vpc.id # Asegurate de usar el nombre con el que definiste tu aws_vpc aquí
}