variable "vpc_cidr" {
  description = "CIDR block para la VPC Hub"
  type        = string
  default     = "10.0.0.0/16"
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
  default     = "production"
}