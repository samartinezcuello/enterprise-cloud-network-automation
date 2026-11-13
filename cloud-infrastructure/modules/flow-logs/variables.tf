variable "name" {
  description = "Name prefix for the log group, KMS key and IAM role."
  type        = string
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "lab"
}

variable "retention_in_days" {
  description = "CloudWatch Logs retention in days (Checkov expects at least 365)."
  type        = number
  default     = 365
}