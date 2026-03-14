variable "allowed_ip" {
  description = "Your personal IP in CIDR notation. Only this address can reach SSH (22) and the Paperclip UI (3100). Example: \"203.0.113.5/32\""
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ip, 0))
    error_message = "allowed_ip must be a valid CIDR block, e.g. \"1.2.3.4/32\"."
  }
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type. Default is t4g.micro (ARM64, ~$6/month). Use t3.micro for Free Tier (x86_64, first 12 months)."
  type        = string
  default     = "t4g.micro"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access. Optional – omit to use SSM Session Manager exclusively."
  type        = string
  default     = null
}
