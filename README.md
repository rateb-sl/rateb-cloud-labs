# Cloud Engineering Labs

A focused portfolio of hands-on AWS, Linux, Terraform, and troubleshooting labs. Each artifact documents the problem, the smallest safe change, the verification evidence, and cleanup.

These are reconstructed, sanitized learning artifacts. They do not include course transcripts, lab instructions, AWS account details, public IP addresses, key files, or credentials.

## Start here

| If you want to see… | Start with… |
| --- | --- |
| Cloud operations and AWS services | [Labs 01–14](#labs) |
| Terraform and infrastructure as code | [Lab 15](labs/15-terraform-remote-s3-backend/) and [Lab 18](labs/18-s3-cloudfront-static-website-terraform/) |
| Troubleshooting and operational reasoning | [Lab 05](labs/05-website-outage-runbook/) and [Lab 16](labs/16-ec2-launch-troubleshooting/) |
| A complete static website path | [Lab 17: AWS CLI](labs/17-s3-cloudfront-static-website-cli/) and [Lab 18: Terraform](labs/18-s3-cloudfront-static-website-terraform/) |
| Terraform fundamentals in a local sandbox | [Lab 19](labs/19-terraform-get-started-localstack/) |

This is the canonical Cloud Engineering portfolio repository. End-to-end applications belong under `projects/` when they have an independent project identity; infrastructure and application code should stay together when they describe one system.

## Labs

| Lab | What it demonstrates |
| --- | --- |
| [01. Verified Linux backup workflow](labs/01-verified-linux-backup/) | Safe archive creation, checksum evidence, restore testing, and a simple audit log. |
| [02. Linux service operations](labs/02-linux-service-operations/) | The difference between a package, a running service, and boot-time enablement. |
| [03. EC2 user data for Apache](labs/03-ec2-user-data-httpd/) | First-boot setup on Amazon Linux 2023 and a practical cloud-init troubleshooting path. |
| [04. VPC and public web server](labs/04-vpc-public-web-server/) | A complete HTTP path through a custom VPC: subnets, route tables, an Internet Gateway, a security group, and EC2 user data. |
| [05. Website outage runbook](labs/05-website-outage-runbook/) | Outside-in troubleshooting of an unreachable website: reproduce, isolate, fix, verify. |
| [06. IAM permissions lab](labs/06-iam-permissions-lab/) | Three users, three permission walls: how policy inheritance and least privilege actually work. |
| [07. Bash scripting challenge](labs/07-bash-scripting-challenge/) | A continuing numbered-files script with no hard-coded starting numbers. |
| [08. AWS security hardening walkthroughs](labs/08-security-hardening-walkthroughs/) | Guided walkthroughs for Amazon Inspector, Systems Manager Patch Manager, and KMS encryption. |
| [09. Cost monitoring with Cost Explorer + Budgets](labs/09-cost-monitoring-explorer-budgets/) | A $100 monthly budget with graduated alerts (50/75/90% actual + 100% forecast) delivered over SNS. |
| [10. Secrets Manager + Lambda](labs/10-secrets-manager-lambda/) | No hardcoded credentials: a Lambda function retrieves a secret at runtime via the Parameters and Secrets extension. |
| [11. Secure EC2 management with Systems Manager](labs/11-secure-ec2-systems-manager/) | Session Manager, Run Command, IAM caller separation, fail-fast troubleshooting, CloudWatch session logging, and cleanup verification. |
| [12. Fine-grained IAM access control](labs/12-fine-grained-iam-access-control/) | Request-context authorization: source IP, tags, MFA, trust/resource/session policies, semantic validation, simulation, and cleanup evidence. |
| [13. Automated patching with Systems Manager](labs/13-automated-patching-systems-manager/) | Patch baseline selection, tag-based targeting, scheduled Scan/Install tasks, compliance evidence, EventBridge alerting, and dependency-aware cleanup. |
| [14. Basic log monitoring with CloudWatch](labs/14-basic-log-monitoring-cloudwatch/) | Plain-text log filtering, custom metrics, alarm evaluation, SNS fan-out, Lambda processing, and cleanup verification. |
| [15. Remote S3 backend for Terraform](labs/15-terraform-remote-s3-backend/) | Remote state storage, backend migration semantics, independent backend/provider regions, and cleanup verification. |
| [16. EC2 launch troubleshooting](labs/16-ec2-launch-troubleshooting/) | Region-scoped AMI troubleshooting, layered HTTP reachability checks, cloud-init evidence, and honest application-test boundaries. |
| [17. S3 + CloudFront static website with the AWS CLI](labs/17-s3-cloudfront-static-website-cli/) | Manual S3 website configuration, public object reads, CloudFront HTTP origin behavior, HTTPS redirect, and cleanup verification. |
| [18. S3 + CloudFront static website with Terraform](labs/18-s3-cloudfront-static-website-terraform/) | Declarative dependency management for S3 website hosting, CloudFront, object uploads, plan review, state read-back, and cleanup. |
| [19. Terraform fundamentals with LocalStack](labs/19-terraform-get-started-localstack/) | Terraform lifecycle, variables, outputs, modules, state, update-in-place versus replacement, and a zero-cost AWS-compatible sandbox. |

## Working principles

- Confirm the host, user, operating system, and target path before changing state.
- Use least privilege. `chmod 777` is not a troubleshooting strategy.
- Treat successful command execution as a starting point, then verify the intended state.
- Keep security groups, AWS IAM, and Linux permissions separate when diagnosing access problems.
- Clean up test resources after each lab to avoid unnecessary cloud cost.

## Repository layout

```text
labs/
├── 01-verified-linux-backup/
├── 02-linux-service-operations/
├── 03-ec2-user-data-httpd/
├── 04-vpc-public-web-server/
├── 05-website-outage-runbook/
├── 06-iam-permissions-lab/
├── 07-bash-scripting-challenge/
├── 08-security-hardening-walkthroughs/
├── 09-cost-monitoring-explorer-budgets/
├── 10-secrets-manager-lambda/
├── 11-secure-ec2-systems-manager/
├── 12-fine-grained-iam-access-control/
├── 13-automated-patching-systems-manager/
├── 14-basic-log-monitoring-cloudwatch/
├── 15-terraform-remote-s3-backend/
├── 16-ec2-launch-troubleshooting/
├── 17-s3-cloudfront-static-website-cli/
├── 18-s3-cloudfront-static-website-terraform/
└── 19-terraform-get-started-localstack/
```

## Scope and safety

Run the examples only in a disposable Linux or AWS test environment. Review paths and service names before use. The scripts deliberately avoid hard-coded identifiers and do not create AWS resources on their own.
