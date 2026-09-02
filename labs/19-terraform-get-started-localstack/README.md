# Terraform fundamentals lab: manage AWS-compatible infrastructure locally

## Goal

Learn the Terraform lifecycle by creating, changing, and destroying a small EC2 and VPC configuration in LocalStack. The transferable pattern is to treat configuration as the source of truth, review the plan, verify state, and clean up deliberately.

## Environment

- Terraform `>= 1.2`
- LocalStack at `http://localhost:4566`
- AWS provider `~> 5.92`
- No real AWS account or cloud cost

The provider uses LocalStack with dummy credentials. The configuration is not a production AWS provider configuration.

## Files

| File | Purpose |
| --- | --- |
| `main.tf` | LocalStack provider, VPC module, and optional EC2 resource example |
| `variables.tf` | Instance name and type inputs |
| `outputs.tf` | Example instance output |

## Run the lab

```bash
cd labs/19-terraform-get-started-localstack
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
terraform output
```

To preview a variable override without applying:

```bash
terraform plan -var='instance_type=t2.large'
```

## Verification

```bash
terraform state list
terraform output
aws --endpoint-url http://localhost:4566 ec2 describe-instances --region us-west-2
```

Expected state depends on which resource blocks are enabled. The repository intentionally keeps the tutorial's resource and output examples commented while the LocalStack module configuration is inspected independently.

## What this lab teaches

- `apply` creates or changes infrastructure from configuration and state.
- Removing a resource block from configuration makes Terraform plan its destruction.
- `terraform destroy` removes the managed infrastructure.
- Input variables and outputs provide controlled interfaces to a configuration.
- Modules package related infrastructure into a reusable block.
- An update-in-place change differs from a change that forces resource replacement.
- A local AWS-compatible sandbox is useful for learning the Terraform workflow without touching a real account.

## Cleanup

```bash
terraform destroy
terraform state list
```

The final state list should be empty after a successful destroy.

## Source note

This lab is a sanitized adaptation of HashiCorp's [Get Started with Terraform on AWS](https://developer.hashicorp.com/terraform/tutorials/aws-get-started) tutorials, adjusted for LocalStack.
