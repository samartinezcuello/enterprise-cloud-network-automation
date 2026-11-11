variable "vpc_cidr" {
  description = "CIDR block for the spoke VPC (must be a /16: the subnet is derived from it)."
  type        = string
  default     = "10.1.0.0/16"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "lab"
}

variable "availability_zone" {
  description = "Availability zone for the spoke subnet."
  type        = string
}
