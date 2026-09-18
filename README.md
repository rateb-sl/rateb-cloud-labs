# Cloud Engineering Portfolio

A verification-first portfolio of hands-on AWS, Linux, Terraform, serverless, containers, and operational troubleshooting work.

Each lab documents the problem, the smallest safe change, the evidence proving the result, and the cleanup or production correction. These are reconstructed, sanitized learning artifacts: no course transcripts, AWS account details, public IP addresses, key files, credentials, or other live identifiers are included.

[Portfolio website](https://rateb-sl.github.io) · [Featured work](#featured-work) · [All labs](#labs)

## Start here

| If you want to evaluate… | Start with… |
| --- | --- |
| End-to-end serverless design | [Lambda sales report workflow](labs/26-lambda-sales-report-workflow/) |
| Event-driven AWS architecture | [S3 event-driven processing](labs/21-s3-event-driven-processing/) |
| Terraform and infrastructure design | [Terraform ALB + Auto Scaling](labs/23-terraform-alb-asg/) |
| Containers and managed compute | [AWS Fargate](labs/25-running-containers-fargate/) |
| API and application integration | [API Gateway + DynamoDB URL shortener](labs/20-api-gateway-dynamodb-url-shortener/) |
| Operational troubleshooting | [Website outage runbook](labs/05-website-outage-runbook/) |

## Featured work

These are the best starting points for understanding the portfolio's range and engineering habits.

| Artifact | Why it matters |
| --- | --- |
| [Lambda sales report workflow](labs/26-lambda-sales-report-workflow/) | Connects EventBridge, Lambda orchestration, VPC database access, IAM, layers, SNS, timeouts, and evidence-led troubleshooting. |
| [Running containers with AWS Fargate](labs/25-running-containers-fargate/) | Traces a container from image build through ECR, ECS, Fargate networking, health checks, scaling, and cleanup. |
| [Terraform ALB + Auto Scaling](labs/23-terraform-alb-asg/) | Demonstrates modular infrastructure, remote state, IMDSv2-safe bootstrap, load-balancer health, and instance refresh. |
| [S3 event-driven processing](labs/21-s3-event-driven-processing/) | Shows prefix notifications, Lambda processing, SQS failure handoff, SNS alerting, CloudWatch evidence, and cleanup. |
| [API Gateway + DynamoDB URL shortener](labs/20-api-gateway-dynamodb-url-shortener/) | Covers REST resource wiring, Lambda proxy integrations, invoke permissions, least-privilege DynamoDB access, and end-to-end testing. |

## What this portfolio demonstrates

- **Troubleshooting:** reproduce the failure, isolate the first broken boundary, apply the smallest safe change, and verify the intended state.
- **Cloud foundations:** IAM, VPCs, routing, security groups, EC2, S3, CloudWatch, Systems Manager, and cost controls.
- **Infrastructure as code:** Terraform and CloudFormation with plan review, state read-back, dependency-aware cleanup, and replacement awareness.
- **Modern application paths:** serverless, event-driven processing, API integration, managed containers, notifications, and scheduled workflows.

## Verification standard

A lab is not considered complete because a command returned exit code 0. The artifacts aim to show:

- configuration read-back;
- functional verification;
- failure isolation where relevant;
- security and permission boundaries;
- cleanup verification;
- production improvements and evidence limits.

This makes the repository a technical evidence index rather than a list of unverified service names.

## Labs

| Lab | Area | What it demonstrates |
| --- | --- | --- |
| [01. Verified Linux backup workflow](labs/01-verified-linux-backup/) | Operations | Safe archive creation, checksum evidence, restore testing, and an audit log. |
| [02. Linux service operations](labs/02-linux-service-operations/) | Operations | The difference between a package, a running service, and boot-time enablement. |
| [03. EC2 user data for Apache](labs/03-ec2-user-data-httpd/) | AWS foundations | First-boot setup on Amazon Linux 2023 and cloud-init troubleshooting. |
| [04. VPC and public web server](labs/04-vpc-public-web-server/) | Networking | A complete HTTP path through a custom VPC, routes, an Internet Gateway, a security group, and EC2 user data. |
| [05. Website outage runbook](labs/05-website-outage-runbook/) | Troubleshooting | Outside-in troubleshooting of an unreachable website: reproduce, isolate, fix, verify. |
| [06. IAM permissions lab](labs/06-iam-permissions-lab/) | Security | Policy inheritance, least privilege, and permission boundaries across multiple users. |
| [07. Bash scripting challenge](labs/07-bash-scripting-challenge/) | Linux | A continuing numbered-files script without a hard-coded starting number. |
| [08. AWS security hardening walkthroughs](labs/08-security-hardening-walkthroughs/) | Security | Inspector, Systems Manager Patch Manager, and KMS encryption walkthroughs. |
| [09. Cost monitoring with Cost Explorer + Budgets](labs/09-cost-monitoring-explorer-budgets/) | FinOps | Graduated budget alerts delivered over SNS and verified against cost signals. |
| [10. Secrets Manager + Lambda](labs/10-secrets-manager-lambda/) | Serverless | Runtime secret retrieval without hardcoded credentials. |
| [11. Secure EC2 management with Systems Manager](labs/11-secure-ec2-systems-manager/) | Operations | Session Manager, Run Command, IAM caller separation, logging, and cleanup. |
| [12. Fine-grained IAM access control](labs/12-fine-grained-iam-access-control/) | Security | Request-context authorization, MFA, trust/resource/session policies, and simulation. |
| [13. Automated patching with Systems Manager](labs/13-automated-patching-systems-manager/) | Operations | Patch baselines, tag targeting, scheduled tasks, compliance evidence, and alerts. |
| [14. Basic log monitoring with CloudWatch](labs/14-basic-log-monitoring-cloudwatch/) | Observability | Log filtering, custom metrics, alarm evaluation, SNS fan-out, and Lambda processing. |
| [15. Remote S3 backend for Terraform](labs/15-terraform-remote-s3-backend/) | IaC | Remote state, backend migration semantics, region separation, and cleanup. |
| [16. EC2 launch troubleshooting](labs/16-ec2-launch-troubleshooting/) | Troubleshooting | Region-scoped AMI diagnosis, layered HTTP checks, and cloud-init evidence. |
| [17. S3 + CloudFront static website with the AWS CLI](labs/17-s3-cloudfront-static-website-cli/) | AWS foundations | Manual S3 website configuration, CloudFront behavior, HTTPS redirect, and cleanup. |
| [18. S3 + CloudFront static website with Terraform](labs/18-s3-cloudfront-static-website-terraform/) | IaC | Declarative S3 and CloudFront dependency management, uploads, state read-back, and cleanup. |
| [19. Terraform fundamentals with LocalStack](labs/19-terraform-get-started-localstack/) | IaC | Terraform lifecycle, variables, outputs, modules, state, and replacement behavior. |
| [20. API Gateway + DynamoDB URL shortener](labs/20-api-gateway-dynamodb-url-shortener/) | Serverless | REST resource wiring, Lambda proxy integrations, invoke permissions, and least-privilege DynamoDB access. |
| [21. S3 event-driven processing](labs/21-s3-event-driven-processing/) | Event-driven | S3 notifications, Lambda processing, SQS failure handoff, SNS alerting, and CloudWatch evidence. |
| [22. CloudFormation + S3](labs/22-cloudformation-s3/) | IaC | Declarative S3 provisioning, encryption, versioning, public-access blocking, and cleanup. |
| [23. Terraform ALB + Auto Scaling](labs/23-terraform-alb-asg/) | IaC | Modular VPC and compute provisioning, remote state, health verification, and instance refresh. |
| [24. Elastic Load Balancing with ALB and NLB](labs/24-elastic-load-balancing-alb-nlb/) | Networking | Layer 7 HTTP and Layer 4 TCP load balancing, health checks, boundaries, and verification. |
| [25. Running containers with AWS Fargate](labs/25-running-containers-fargate/) | Containers | Docker, ECR, ECS task definitions, Fargate networking, health checks, scaling, and cleanup. |
| [26. Lambda sales report workflow](labs/26-lambda-sales-report-workflow/) | Serverless | EventBridge, Lambda orchestration, VPC database access, IAM, layers, SNS, timeouts, and evidence. |

## Working principles

- Confirm the host, user, operating system, and target path before changing state.
- Use least privilege. `chmod 777` is not a troubleshooting strategy.
- Treat successful command execution as a starting point, then verify the intended state.
- Keep security groups, AWS IAM, and Linux permissions separate when diagnosing access problems.
- Clean up test resources after each lab to avoid unnecessary cloud cost.

## Repository structure

- `labs/` — the canonical, numbered learning and portfolio artifacts.
- `projects/` — reserved for independent end-to-end projects with their own purpose, README, lifecycle, and audience.

## Scope and safety

Run the examples only in a disposable Linux or AWS test environment. Review paths and service names before use. The scripts deliberately avoid hard-coded identifiers and do not create AWS resources on their own.
