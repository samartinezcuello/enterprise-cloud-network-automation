output "log_group_name" {
  description = "Name of the CloudWatch log group that receives the flow logs."
  value       = aws_cloudwatch_log_group.flow_logs.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group that receives the flow logs."
  value       = aws_cloudwatch_log_group.flow_logs.arn
}

output "role_arn" {
  description = "ARN of the IAM role used by VPC Flow Logs."
  value       = aws_iam_role.flow_logs.arn
}

output "log_format" {
  description = "Custom flow log record format."
  value       = local.log_format
}