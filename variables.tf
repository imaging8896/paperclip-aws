variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-northeast-1"
}

variable "instance_type" {
  description = "EC2 instance type. Default is t4g.small (ARM64, ~$12/month). Use t3.micro for Free Tier (x86_64, first 12 months)."
  type        = string
  default     = "t4g.small"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access. Optional – omit to use SSM Session Manager exclusively."
  type        = string
  default     = null
}

variable "anthropic_api_key" {
  description = "Anthropic API key for Claude CLI. Required for Paperclip to work."
  type        = string
  sensitive   = true
}
