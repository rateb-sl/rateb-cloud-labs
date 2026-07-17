# AWS and Linux lab notes

A small collection of hands-on lab write-ups from my AWS Cloud Computing training. I use this repository to show how I approach basic cloud operations: inspect the environment first, make the smallest safe change, verify the result, and document what I learned.

These are reconstructed, sanitized learning artifacts. They do not include course transcripts, lab instructions, AWS account details, public IP addresses, key files, or credentials.

## Labs

| Lab | What it demonstrates |
| --- | --- |
| [01. Verified Linux backup workflow](labs/01-verified-linux-backup/) | Safe archive creation, checksum evidence, restore testing, and a simple audit log. |
| [02. Linux service operations](labs/02-linux-service-operations/) | The difference between a package, a running service, and boot-time enablement. |
| [03. EC2 user data for Apache](labs/03-ec2-user-data-httpd/) | First-boot setup on Amazon Linux 2023 and a practical cloud-init troubleshooting path. |

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
└── 03-ec2-user-data-httpd/
```

## Scope and safety

Run the examples only in a disposable Linux or AWS test environment. Review paths and service names before use. The scripts deliberately avoid hard-coded identifiers and do not create AWS resources on their own.

## Background

I am moving from technical support and client operations into cloud engineering. These labs document the practical habits I am building: working safely in Linux, troubleshooting from evidence, and turning repeatable steps into small pieces of automation.
