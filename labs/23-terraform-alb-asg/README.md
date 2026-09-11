# Terraform ALB + Auto Scaling: make infrastructure repeatable and observable

## Goal

Build a public HTTP service with Terraform and make the full infrastructure lifecycle repeatable:

```text
Terraform root module
        ├── VPC module
        │   ├── VPC, public subnets, routes, Internet Gateway
        │   └── ALB and web security-group boundaries
        └── compute module
            ├── IMDSv2-hardened EC2 launch template
            ├── Auto Scaling Group
            ├── Application Load Balancer
            └── target group, listener, and scaling policies
```

The transferable pattern is to express resources and relationships as a dependency graph, review the graph with `plan`, apply only the reviewed plan, verify AWS state and the application path independently, and clean up every billable resource.

## Environment

- Terraform 1.x
- HashiCorp AWS provider 6.x
- AWS CLI with an authenticated named profile
- A disposable AWS account or sandbox
- One selected AWS Region
- S3 remote state with DynamoDB locking, bootstrapped outside this configuration

The examples contain no credentials, live account identifiers, ARNs, instance IDs, public IPs, backend bucket names, or private state. Copy an environment example to `terraform.tfvars` before running the workflow locally.

## Design decisions

### Dependency order

```text
backend prerequisites
  → Terraform initialization
  → VPC and network relationships
  → security groups
  → IAM instance profile
  → launch template
  → target group and ALB
  → Auto Scaling Group
  → health and HTTP verification
  → destroy managed resources
  → remove backend resources
```

Terraform derives most ordering from references such as `vpc_id = module.vpc.vpc_id`; the configuration does not depend on a hand-written sequence of AWS CLI creation commands.

### Network boundaries

- The ALB accepts public HTTP traffic on port 80.
- The web security group accepts port 80 only from the ALB security group.
- The subnets are public because they have a route to the Internet Gateway and map public IPv4 addresses on launch.
- SSH is not exposed.

### Instance bootstrap and metadata

The launch template enforces IMDSv2. The bootstrap script first obtains a metadata token, then uses it to request the instance ID and Availability Zone. This matters because IMDSv1-style requests can return empty values when IMDSv2 is required.

The template also demonstrates the boundary between Terraform-time and shell-time interpolation:

```text
${project_name}       → rendered by Terraform
$${INSTANCE_ID}       → emitted as ${INSTANCE_ID}, evaluated on EC2
```

### Remote state

The state bucket and lock table are external prerequisites. This avoids the chicken-and-egg problem of asking Terraform to create the storage that Terraform itself needs to store state. The S3 backend `dynamodb_table` setting currently produces a deprecation warning with newer Terraform versions; it remains in this lab because DynamoDB locking is part of the exercise. A separate migration should evaluate the newer native lockfile option.

## Run

Create a local variable file from the safe example:

```bash
cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars
```

Create a private local backend-values file containing only the selected non-secret names:

```bash
# Keep backend values outside Git. Do not put credentials in this file.
source .backend-vars.sh
```

Initialize with the real backend values supplied by your environment:

```bash
terraform init \
  -input=false \
  -reconfigure \
  -backend-config="bucket=$BUCKET_NAME" \
  -backend-config="key=terraform.tfstate" \
  -backend-config="region=$AWS_REGION" \
  -backend-config="dynamodb_table=$LOCK_TABLE_NAME" \
  -backend-config="encrypt=true"
```

Validate, plan, and apply only after reviewing the plan:

```bash
terraform fmt -check -recursive
terraform validate
terraform plan \
  -var-file="environments/dev/terraform.tfvars" \
  -out=tfplan
terraform apply tfplan
```

The `deploy.sh` and `state.sh` scripts provide guarded environment selection and state inspection. The CodeBuild file is a CI template for formatting, validation, and plan generation; production CI should inject backend configuration through a protected environment or secret-management path and should keep apply behind an approval gate.

## Verification

### Terraform state

```bash
terraform state list
terraform plan \
  -detailed-exitcode \
  -var-file="environments/dev/terraform.tfvars"
```

`terraform state list` proves Terraform tracks the expected resources. A detailed plan exit code of `0` proves no configuration drift was detected at that moment; it does not prove the application is reachable.

### ALB target health

```bash
TARGET_GROUP_ARN="$(terraform output -raw target_group_arn)"
aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --region "$AWS_REGION" \
  --query 'TargetHealthDescriptions[].TargetHealth.State' \
  --output json
```

Expected evidence is two healthy target states. This proves the ALB can reach both registered instances on `/health`.

### Public application response

```bash
ALB_DNS="$(terraform output -raw alb_dns_name)"
curl -fsS --max-time 10 "http://${ALB_DNS}/"
```

The response should contain the project heading, a non-empty instance ID, and a non-empty Availability Zone. A successful HTTP response proves the public request path at that moment; it does not prove every backend answered.

### Observe both backends

```bash
for i in {1..10}; do
  curl -sS --max-time 10 "http://${ALB_DNS}/" \
    | grep -oE 'Instance ID:</strong> [^<]+'
done | sort | uniq -c
```

Two distinct instance IDs demonstrate that requests reached both backends. Uneven counts are normal and are not a guarantee of equal distribution.

### Auto Scaling capacity

```bash
ASG_NAME="${PROJECT_NAME}-web-asg"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --region "$AWS_REGION" \
  --query 'AutoScalingGroups[0].{Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,Instances:length(Instances),LifecycleStates:Instances[].LifecycleState}' \
  --output json
```

The development example is expected to show a minimum and desired capacity of two, a maximum of four, two instances, and `InService` lifecycle states.

### Observed execution

The private execution produced these evidence types:

| Check | Observed result |
| --- | --- |
| Initial plan | 21 resources to add; no changes or destroys |
| Initial apply | 21 resources added |
| State | 21 managed resources plus two data sources |
| Target health | Two healthy targets |
| Public HTTP | Expected Terraform page returned successfully |
| ASG capacity | Two instances, both `InService` |
| Bootstrap correction | IMDSv2 metadata token flow added after empty metadata was detected |
| Instance refresh | Completed successfully at 100% |
| Final plan | No changes after the launch-template correction and refresh |
| Load distribution | Ten requests reached two distinct backend instance IDs |

The specific AWS identifiers are intentionally omitted from this public artifact.

## Cost and safety

The ALB, EC2 instances, public IPv4 addresses, S3 bucket, and DynamoDB table can incur charges while they exist. Review the plan and destroy the stack promptly after verification. Keep state private, use a least-privileged named profile, avoid SSH exposure, and never commit `.terraform/`, state files, credentials, or backend values.

## Cleanup

Destroy Terraform-managed resources before deleting the backend:

```bash
terraform plan \
  -destroy \
  -var-file="environments/dev/terraform.tfvars" \
  -out=destroy.tfplan
terraform apply destroy.tfplan
terraform state list
```

The state list must be empty before deleting the remote state object and backend resources. For a versioned S3 bucket, inspect and remove object versions and delete markers before deleting the bucket. Then delete the DynamoDB lock table and verify both backend resources are absent.

Do not delete the backend first. Terraform needs its state to destroy the infrastructure it manages.

## What this lab teaches

- Terraform configuration is a dependency graph, not a shell script with a fixed creation order.
- `plan` is the review boundary; `apply` changes AWS; state and service read-backs are separate evidence layers.
- IMDSv2 hardening must be reflected in bootstrap code.
- A launch-template update does not prove existing instances received new user data; an instance refresh closes that gap.
- Remote state storage, locking, provider-region selection, application verification, and cleanup are separate operational concerns.
