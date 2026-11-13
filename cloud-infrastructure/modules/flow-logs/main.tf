data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  account_id     = data.aws_caller_identity.current.account_id
  region         = data.aws_region.current.name
  log_group_name = "/aws/vpc/flow-logs/${var.name}"

  # Built by hand (not from the log group resource) to avoid a dependency cycle
  # between the KMS key policy and the log group that uses the key.
  log_group_arn = "arn:aws:logs:${local.region}:${local.account_id}:log-group:${local.log_group_name}"

  # Custom format: adds vpc-id, subnet-id, direction and the original packet
  # addresses (pkt-*), which show the real source/destination behind NAT and the TGW.
  log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${flow-direction} $${pkt-srcaddr} $${pkt-dstaddr}"
}

# ---------------------------------------------------------------------------
# KMS key to encrypt the logs
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "kms" {
  # checkov:skip=CKV_AWS_109: KMS key policies are resource-based; "*" refers to the key itself
  # checkov:skip=CKV_AWS_111: KMS key policies are resource-based; "*" refers to the key itself
  # checkov:skip=CKV_AWS_356: KMS key policies are resource-based; "*" refers to the key itself
  statement {
    sid       = "EnableAccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid = "AllowCloudWatchLogsToUseTheKey"

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = [local.log_group_arn]
    }
  }
}

resource "aws_kms_key" "logs" {
  description             = "Encrypts VPC flow logs (${var.name})"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms.json

  tags = {
    Name = "${var.name}-flow-logs-key"
  }
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${var.name}-flow-logs"
  target_key_id = aws_kms_key.logs.key_id
}

# ---------------------------------------------------------------------------
# Log group
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = local.log_group_name
  retention_in_days = var.retention_in_days
  kms_key_id        = aws_kms_key.logs.arn

  tags = {
    Name        = local.log_group_name
    Environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# IAM role that lets the VPC Flow Logs service write into the log group
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    # Confused-deputy protection: only flow logs of this account can assume the role
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ec2:${local.region}:${local.account_id}:vpc-flow-log/*"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.name}-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json

  tags = {
    Name = "${var.name}-flow-logs-role"
  }
}

data "aws_iam_policy_document" "flow_logs_write" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]

    resources = [
      aws_cloudwatch_log_group.flow_logs.arn,
      "${aws_cloudwatch_log_group.flow_logs.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "write-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_write.json
}