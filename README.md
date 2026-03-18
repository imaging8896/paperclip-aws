# paperclip-aws

Terraform infrastructure to self-host [Paperclip](https://github.com/paperclipai/paperclip) for a single user at minimum cost.

## Architecture

| Resource | Detail | Est. cost (us-east-1) |
|---|---|---|
| EC2 `t4g.micro` | ARM64, 2 vCPU, 1 GiB RAM | ~$6.05 / month |
| EBS `gp3` 20 GB | Root volume | ~$1.60 / month |
| Elastic IP | Stable public IP (free while attached) | $0.00 / month |
| VPC (single public subnet) | No NAT gateway | $0.00 / month |
| **Total** | | **~$7.65 / month** |

> **AWS Free Tier:** If your account is within its first 12 months, set `instance_type = "t3.micro"` (x86) to use the 750 hrs/month free allowance.

### Access control

Port **3100** (Paperclip web UI) is **not exposed to the internet**. You access the UI by forwarding the port over SSH to your local machine:

```bash
ssh -N -L 3100:localhost:3100 ec2-user@<elastic-ip>
```

Then open **http://localhost:3100** in your browser.

This approach works regardless of your local IP address (static or dynamic) and avoids exposing the UI publicly.

Port **22** (SSH) is open from `0.0.0.0/0` so you can connect from any IP.

SSM Session Manager is also enabled on the instance role. If you prefer not to open port 22, you can use the AWS CLI to forward the port without SSH:

```bash
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3100"],"localPortNumber":["3100"]}'
```

## Prerequisites

- [Terraform 1.5+](https://developer.hashicorp.com/terraform/install)
- AWS CLI configured with credentials (`aws configure`)
- An EC2 key pair in your target region (for SSH tunnel access)

## Quick start

```bash
# 1. Initialise Terraform (downloads the AWS provider)
terraform init

# 2. Deploy (pass your EC2 key pair name for SSH access)
terraform apply -var="key_name=<your-key-pair>"
```

After `apply` finishes, Terraform prints:

```
paperclip_url       = "http://localhost:3100"
public_ip           = "<elastic-ip>"
ssh_tunnel_command  = "ssh -N -L 3100:localhost:3100 ec2-user@<elastic-ip>"
ssh_command         = "ssh ec2-user@<elastic-ip>"
```

> The instance needs ~3–5 minutes after launch to install Node.js, pnpm, clone Paperclip, build it, and start the service.

### Open the Paperclip UI

```bash
# 1. Start the SSH tunnel (keep this terminal open)
ssh -N -L 3100:localhost:3100 ec2-user@<elastic-ip>

# 2. Open http://localhost:3100 in your browser
```

### Check boot progress

```bash
ssh ec2-user@<elastic-ip>
sudo tail -f /var/log/paperclip-bootstrap.log
journalctl -fu paperclip
```

## Variables

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region to deploy into |
| `instance_type` | `t4g.micro` | EC2 instance type |
| `key_name` | `null` | EC2 key pair name for SSH tunnel access |

Variables can be set on the command line, in `terraform.tfvars`, or as environment variables (`TF_VAR_*`):

```bash
# terraform.tfvars (gitignored)
instance_type = "t3.micro"
key_name      = "my-key-pair"
```

## Useful commands

| Command | Description |
|---|---|
| `terraform init` | Initialise and download providers |
| `terraform plan` | Preview changes |
| `terraform apply` | Deploy / update the stack |
| `terraform destroy` | Tear down all resources |
| `terraform output` | Show outputs of a deployed stack |

## Updating Paperclip

SSH into the instance (or use SSM Session Manager) and pull the latest code:
```bash
ssh ec2-user@<elastic-ip>
cd ~/paperclip
git pull
pnpm install --frozen-lockfile
pnpm build
sudo systemctl restart paperclip
```

