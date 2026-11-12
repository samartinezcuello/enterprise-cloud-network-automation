# Latest Amazon Linux 2023 AMI, resolved through the public SSM parameter
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# IAM role so the instance can register with SSM Session Manager (no SSH, no key pair)
data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm" {
  name               = "${var.name}-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json

  tags = {
    Name = "${var.name}-ssm-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.name}-ssm-profile"
  role = aws_iam_role.ssm.name
}

# No inbound rules at all; outbound HTTPS only (SSM and the egress test)
resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "Test instance: no inbound, HTTPS outbound only"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS to anywhere (SSM and egress test)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_instance" "this" {
  # checkov:skip=CKV_AWS_126: Detailed monitoring is billed per instance and not needed for a short-lived lab
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm.name
  associate_public_ip_address = false
  ebs_optimized               = true
  monitoring                  = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }

  tags = {
    Name        = var.name
    Environment = var.environment
  }
}