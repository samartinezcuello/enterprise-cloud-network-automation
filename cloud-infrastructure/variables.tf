variable "region" {
  description = "AWS region for the lab."
  type        = string
  default     = "us-east-1"
}

variable "az_suffix" {
  description = "Availability zone letter appended to the region (for example 'a' gives us-east-1a)."
  type        = string
  default     = "a"
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

variable "deploy_test_instance" {
  description = "Create a small test instance in the spoke (reachable only through SSM). Requires enable_nat_gateway = true."
  type        = bool
  default     = false
}