import * as cdk from "aws-cdk-lib";
import {
  aws_ec2 as ec2,
  aws_iam as iam,
  CfnOutput,
} from "aws-cdk-lib";
import { Construct } from "constructs";
import * as fs from "fs";
import * as path from "path";

export interface PaperclipAwsStackProps extends cdk.StackProps {
  /**
   * CIDR notation for the personal IP address that is allowed to access
   * the Paperclip UI and SSH.  Example: "203.0.113.5/32"
   */
  readonly allowedIp: string;

  /**
   * EC2 instance type.  Defaults to t4g.micro (ARM64, lowest-cost
   * general-purpose instance, ~$6.05/month in us-east-1).
   */
  readonly instanceType?: ec2.InstanceType;
}

/**
 * Minimum-cost single-user Paperclip deployment on AWS.
 *
 * Resources created:
 *  - VPC with one public subnet (no NAT gateway → zero extra cost)
 *  - EC2 t4g.micro with Amazon Linux 2023 ARM64
 *  - Security group that allows SSH (22) and Paperclip UI (3100)
 *    only from the personal IP
 *  - Elastic IP attached to the instance
 *  - IAM instance profile with SSM access (passwordless terminal)
 *  - User-data script that installs Node 20, pnpm, clones Paperclip
 *    and registers it as a systemd service
 *
 * Estimated monthly cost (us-east-1, 2025):
 *  - t4g.micro:   ~$6.05
 *  - EBS gp3 8GB: ~$0.64
 *  - Elastic IP:  $0.00 (free while attached)
 *  - Total:       ~$6.69 / month
 *
 * AWS Free Tier (first 12 months):
 *  - t2.micro / t3.micro is free-tier eligible; swap instanceType if desired.
 */
export class PaperclipAwsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: PaperclipAwsStackProps) {
    super(scope, id, props);

    const { allowedIp } = props;
    const instanceType =
      props.instanceType ??
      new ec2.InstanceType("t4g.micro");

    // ── VPC ────────────────────────────────────────────────────────────────
    // Single public subnet in one AZ.  No NAT gateway avoids the
    // ~$32/month NAT gateway cost.
    const vpc = new ec2.Vpc(this, "Vpc", {
      maxAzs: 1,
      natGateways: 0,
      subnetConfiguration: [
        {
          name: "Public",
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 28,
        },
      ],
    });

    // ── Security Group ─────────────────────────────────────────────────────
    // Only the personal IP can reach SSH and the Paperclip web UI.
    const sg = new ec2.SecurityGroup(this, "PaperclipSg", {
      vpc,
      description: "Allow SSH and Paperclip UI from personal IP only",
      allowAllOutbound: true,
    });

    sg.addIngressRule(
      ec2.Peer.ipv4(allowedIp),
      ec2.Port.tcp(22),
      "SSH from personal IP"
    );

    sg.addIngressRule(
      ec2.Peer.ipv4(allowedIp),
      ec2.Port.tcp(3100),
      "Paperclip web UI from personal IP"
    );

    // ── IAM Role ───────────────────────────────────────────────────────────
    // SSM Session Manager lets you open a terminal from the AWS console
    // without opening port 22.  SSH rule above is kept for convenience.
    const role = new iam.Role(this, "PaperclipRole", {
      assumedBy: new iam.ServicePrincipal("ec2.amazonaws.com"),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName(
          "AmazonSSMManagedInstanceCore"
        ),
      ],
    });

    // ── AMI ────────────────────────────────────────────────────────────────
    // Amazon Linux 2023 ARM64 (matched to t4g instance family).
    const machineImage = ec2.MachineImage.latestAmazonLinux2023({
      cpuType: ec2.AmazonLinuxCpuType.ARM_64,
    });

    // ── User data ──────────────────────────────────────────────────────────
    const userDataScript = fs.readFileSync(
      path.join(__dirname, "..", "scripts", "user-data.sh"),
      "utf8"
    );
    const userData = ec2.UserData.forLinux();
    userData.addCommands(userDataScript);

    // ── EC2 Instance ───────────────────────────────────────────────────────
    const instance = new ec2.Instance(this, "PaperclipInstance", {
      vpc,
      instanceType,
      machineImage,
      securityGroup: sg,
      role,
      userData,
      // gp3 is cheaper and faster than gp2; 20 GB gives ample space for
      // Node.js, pnpm, the Paperclip monorepo, and the embedded PostgreSQL
      // database (~$1.60/month in us-east-1).
      blockDevices: [
        {
          deviceName: "/dev/xvda",
          volume: ec2.BlockDeviceVolume.ebs(20, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            deleteOnTermination: true,
          }),
        },
      ],
      // Require IMDSv2 to prevent SSRF attacks against the metadata service
      requireImdsv2: true,
    });

    // ── Elastic IP ─────────────────────────────────────────────────────────
    // Free while the instance is running; $0.005/hr when stopped.
    const eip = new ec2.CfnEIP(this, "PaperclipEip", {
      domain: "vpc",
    });

    new ec2.CfnEIPAssociation(this, "PaperclipEipAssoc", {
      allocationId: eip.attrAllocationId,
      instanceId: instance.instanceId,
    });

    // ── Outputs ────────────────────────────────────────────────────────────
    new CfnOutput(this, "PaperclipUrl", {
      value: cdk.Fn.join("", ["http://", eip.ref, ":3100"]),
      description: "Paperclip web UI URL (available after ~3 min boot)",
    });

    new CfnOutput(this, "PublicIp", {
      value: eip.ref,
      description: "Elastic IP address of the instance",
    });

    new CfnOutput(this, "SshCommand", {
      value: cdk.Fn.join("", ["ssh -i ~/.ssh/<your-key>.pem ec2-user@", eip.ref]),
      description: "SSH command (add KeyPair via key-pair name in instance props if needed)",
    });
  }
}
