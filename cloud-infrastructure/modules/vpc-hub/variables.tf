variable "vpc_cidr" {
  description = "CIDR block for the hub VPC (must be a /16: subnets are derived from it)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "lab"
}

variable "availability_zone" {
  description = "Availability zone for the hub subnets."
  type        = string
}

variable "enable_nat_gateway" {
  description = "Create a NAT Gateway in the public subnet and route the TGW attachment subnet through it. Billed per hour."
  type        = bool
  default     = false
}
