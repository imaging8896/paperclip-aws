# =============================================================================
# Paperclip — minimum-cost single-user self-hosted deployment on AWS
# =============================================================================

locals {
  name = "paperclip"

  # Detect Graviton (ARM64) instance families so we can select the right AMI.
  is_arm = can(regex("^(t4g|c6g|c7g|m6g|m7g|r6g|r7g)", var.instance_type))
  arch   = local.is_arm ? "arm64" : "x86_64"
}

# ── AMI ────────────────────────────────────────────────────────────────────
# Resolve the latest Amazon Linux 2023 AMI for the chosen architecture
# using the AWS-maintained SSM parameter path.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${local.arch}"
}

# ── VPC ────────────────────────────────────────────────────────────────────
# Single public subnet in one AZ.  No NAT gateway avoids the ~$32/month cost.
resource "aws_vpc" "paperclip" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = local.name }
}

resource "aws_internet_gateway" "paperclip" {
  vpc_id = aws_vpc.paperclip.id
  tags   = { Name = local.name }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.paperclip.id
  cidr_block              = "10.0.0.0/28"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "${local.name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.paperclip.id
  tags   = { Name = "${local.name}-public" }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.paperclip.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ── Security Group ─────────────────────────────────────────────────────────
# SSH is open from anywhere so the user can connect from a dynamic IP and
# forward port 3100 to their local machine via an SSH tunnel.
# Port 3100 is intentionally NOT exposed publicly — the Paperclip UI is
# accessed exclusively through the tunnel (http://localhost:3100).
resource "aws_security_group" "paperclip" {
  name        = local.name
  description = "Allow SSH from anywhere; Paperclip UI via SSH tunnel only"
  vpc_id      = aws_vpc.paperclip.id

  ingress {
    description = "SSH from anywhere - use SSH tunnel for UI access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = local.name }
}

# ── IAM Role ───────────────────────────────────────────────────────────────
# SSM Session Manager lets you open a terminal from the AWS console
# without a key pair.  It can also be used for port-forwarding instead of
# a traditional SSH tunnel if preferred.
resource "aws_iam_role" "paperclip" {
  name = local.name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = local.name }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.paperclip.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "paperclip" {
  name = local.name
  role = aws_iam_role.paperclip.name
}

# ── EC2 Instance ───────────────────────────────────────────────────────────
resource "aws_instance" "paperclip" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.paperclip.id]
  iam_instance_profile   = aws_iam_instance_profile.paperclip.name
  key_name               = var.key_name
  user_data = templatefile("${path.module}/scripts/user-data.sh", {
    anthropic_api_key = var.anthropic_api_key
  })

  # gp3 is cheaper and faster than gp2; 20 GB gives ample space for
  # Node.js, pnpm, the Paperclip monorepo, and the embedded PostgreSQL
  # database (~$1.60/month in us-east-1).
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
  }

  # Require IMDSv2 to prevent SSRF attacks against the metadata service.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = { Name = local.name }
}

# ── Elastic IP ─────────────────────────────────────────────────────────────
# Free while the instance is running; $0.005/hr when stopped.
resource "aws_eip" "paperclip" {
  domain   = "vpc"
  instance = aws_instance.paperclip.id
  tags     = { Name = local.name }

  depends_on = [aws_internet_gateway.paperclip]
}
