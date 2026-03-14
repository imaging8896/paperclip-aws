# paperclip-aws

AWS CDK infrastructure to self-host [Paperclip](https://github.com/paperclipai/paperclip) for a single user at minimum cost.

## Architecture

| Resource | Detail | Est. cost (us-east-1) |
|---|---|---|
| EC2 `t4g.micro` | ARM64, 2 vCPU, 1 GiB RAM | ~$6.05 / month |
| EBS `gp3` 20 GB | Root volume | ~$1.60 / month |
| Elastic IP | Stable public IP (free while attached) | $0.00 / month |
| VPC (single public subnet) | No NAT gateway | $0.00 / month |
| **Total** | | **~$7.65 / month** |

> **AWS Free Tier:** If your account is within its first 12 months, swap the instance type to `t3.micro` (x86) to use the 750 hrs/month free allowance. Pass `-c instanceType=t3.micro` when deploying.

### Access control

The Security Group allows **only your personal IP** to reach:
- Port **22** (SSH)
- Port **3100** (Paperclip web UI)

All other inbound traffic is dropped.

SSM Session Manager is also enabled on the instance role, so you can open a browser-based terminal from the AWS Console without needing to open port 22.

## Prerequisites

- [Node.js 20+](https://nodejs.org/)
- [AWS CDK v2](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html): `npm install -g aws-cdk`
- AWS CLI configured with credentials (`aws configure`)

## Quick start

```bash
# 1. Install dependencies
npm install

# 2. Bootstrap CDK in your account/region (one-time)
npx cdk bootstrap

# 3. Find your public IP
curl -s https://checkip.amazonaws.com

# 4. Deploy
npx cdk deploy -c allowedIp=<your-ip>/32
```

The stack outputs the Paperclip URL once deployed:
```
PaperclipAwsStack.PaperclipUrl = http://<elastic-ip>:3100
```

> The instance needs ~3–5 minutes after launch to install Node.js, pnpm, clone Paperclip, build it, and start the service. Check progress with:
> ```bash
> ssh ec2-user@<elastic-ip>
> sudo tail -f /var/log/paperclip-bootstrap.log
> journalctl -fu paperclip
> ```

## Useful commands

| Command | Description |
|---|---|
| `npx cdk synth -c allowedIp=x.x.x.x/32` | Emit CloudFormation template |
| `npx cdk diff -c allowedIp=x.x.x.x/32` | Compare deployed vs local |
| `npx cdk deploy -c allowedIp=x.x.x.x/32` | Deploy / update the stack |
| `npx cdk destroy` | Tear down all resources |

## Customisation

| Context variable | Default | Description |
|---|---|---|
| `allowedIp` | *(required)* | CIDR of your personal IP, e.g. `1.2.3.4/32` |
| `instanceType` | `t4g.micro` | EC2 instance type |

Pass additional context with `-c key=value`. For example:
```bash
npx cdk deploy -c allowedIp=1.2.3.4/32 -c instanceType=t3.micro
```

## Updating Paperclip

SSH into the instance and pull the latest code:
```bash
ssh ec2-user@<elastic-ip>
cd ~/paperclip
git pull
pnpm install --frozen-lockfile
pnpm build
sudo systemctl restart paperclip
```
