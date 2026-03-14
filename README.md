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

The Security Group allows **only your personal IP** to reach:
- Port **22** (SSH)
- Port **3100** (Paperclip web UI)

All other inbound traffic is dropped.

SSM Session Manager is also enabled on the instance role, so you can open a browser-based terminal from the AWS Console without needing a key pair or an open SSH port.

## Prerequisites

- [Terraform 1.5+](https://developer.hashicorp.com/terraform/install)
- AWS CLI configured with credentials (`aws configure`)

## Quick start

```bash
# 1. Initialise Terraform (downloads the AWS provider)
terraform init

# 2. Find your public IP
curl -s https://checkip.amazonaws.com

# 3. Deploy
terraform apply -var="allowed_ip=<your-ip>/32"
```

Terraform prints the Paperclip URL at the end of `apply`:
```
paperclip_url = "http://<elastic-ip>:3100"
```

> The instance needs ~3–5 minutes after launch to install Node.js, pnpm, clone Paperclip, build it, and start the service. Check progress with:
> ```bash
> ssh ec2-user@<elastic-ip>          # if key_name was set
> sudo tail -f /var/log/paperclip-bootstrap.log
> journalctl -fu paperclip
> ```

## Variables

| Variable | Default | Description |
|---|---|---|
| `allowed_ip` | *(required)* | Your personal IP in CIDR notation, e.g. `1.2.3.4/32` |
| `aws_region` | `us-east-1` | AWS region to deploy into |
| `instance_type` | `t4g.micro` | EC2 instance type |
| `key_name` | `null` | EC2 key pair name for SSH (optional) |

Variables can be set on the command line, in `terraform.tfvars`, or as environment variables (`TF_VAR_*`):

```bash
# Command line
terraform apply -var="allowed_ip=1.2.3.4/32" -var="instance_type=t3.micro"

# terraform.tfvars (gitignored)
allowed_ip    = "1.2.3.4/32"
instance_type = "t3.micro"
key_name      = "my-key-pair"
```

## Useful commands

| Command | Description |
|---|---|
| `terraform init` | Initialise and download providers |
| `terraform plan -var="allowed_ip=x.x.x.x/32"` | Preview changes |
| `terraform apply -var="allowed_ip=x.x.x.x/32"` | Deploy / update the stack |
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

