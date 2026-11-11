variable "region" {
  description = "AWS region for the lab."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name used as a tag on all resources."
  type        = string
  default     = "enterprise-cloud-network-automation"
}

variable "environment" {
  description = "Deployment environment name (this repository is a lab)."
  type        = string
  default     = "lab"
}

variable "hub_vpc_cidr" {
  description = "CIDR block for the hub VPC (must be a /16)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "spoke_vpc_cidr" {
  description = "CIDR block for the spoke VPC (must be a /16)."
  type        = string
  default     = "10.1.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Create the hub NAT Gateway and centralized egress routes. Billed per hour: enable only while testing, then destroy."
  type        = bool
  default     = false
}
