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
