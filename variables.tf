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

variable "use_docker" {
  description = <<-EOT
    When true, run Paperclip via Docker Compose (production server + PostgreSQL container)
    using the official Dockerfile from the Paperclip repository.

    Cost comparison:
      false (default) – native build: t4g.micro + 20 GB gp3 ≈ $7.65 / month
      true  – Docker Compose:  t4g.small + 30 GB gp3 ≈ $14.54 / month

    The Docker path requires a t4g.small (2 GiB RAM) to comfortably run both the
    PostgreSQL container and the Node.js server container side-by-side.
    It also enables production mode with authentication (BETTER_AUTH_SECRET).
  EOT
  type        = bool
  default     = false
}
