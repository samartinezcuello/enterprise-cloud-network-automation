variable "name" {
  description = "Name prefix for the instance and its IAM and security resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "lab"
}

variable "vpc_id" {
  description = "ID of the VPC where the instance runs."
  type        = string
}

variable "subnet_id" {
  description = "ID of the (private) subnet where the instance runs."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}