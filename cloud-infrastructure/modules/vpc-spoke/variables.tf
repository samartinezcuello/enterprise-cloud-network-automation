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

# ---------------------------------------------------------------------------
# Step - New module Flow Log
# ---------------------------------------------------------------------------
variable "flow_log_destination_arn" {
  description = "ARN of the CloudWatch log group that receives the VPC flow logs."
  type        = string
}

variable "flow_log_role_arn" {
  description = "ARN of the IAM role used by VPC Flow Logs to write to the log group."
  type        = string
}

variable "flow_log_format" {
  description = "Custom flow log record format."
  type        = string
}