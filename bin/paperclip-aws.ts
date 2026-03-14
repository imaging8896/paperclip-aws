#!/usr/bin/env node
import "source-map-support/register";
import * as cdk from "aws-cdk-lib";
import { aws_ec2 as ec2 } from "aws-cdk-lib";
import { PaperclipAwsStack } from "../lib/paperclip-aws-stack";

const app = new cdk.App();

// Read the allowed IP from CDK context (required)
const allowedIp: string = app.node.tryGetContext("allowedIp");
if (!allowedIp) {
  throw new Error(
    "CDK context variable 'allowedIp' is required.\n" +
      "Pass it with: cdk deploy -c allowedIp=<your-public-ip>/32"
  );
}

// Optional instance type override (default: t4g.micro)
const instanceTypeStr: string | undefined = app.node.tryGetContext("instanceType");
const instanceType = instanceTypeStr
  ? new ec2.InstanceType(instanceTypeStr)
  : undefined;

new PaperclipAwsStack(app, "PaperclipAwsStack", {
  allowedIp,
  instanceType,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: "Single-user Paperclip self-hosted deployment (minimum cost)",
});
