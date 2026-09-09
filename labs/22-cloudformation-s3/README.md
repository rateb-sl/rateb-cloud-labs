# CloudFormation + S3: define a secure bucket once and verify the real state

## Goal

Use AWS CloudFormation to define one S3 bucket as repeatable infrastructure rather than creating it manually. The template enables versioning, default AES-256 encryption, and all four S3 Block Public Access controls.

The transferable pattern is **template → validate → deploy → read state back → test → clean up**. A successful stack request is not completion evidence; the stack status and the underlying S3 configuration must be read back separately.

## Environment

- AWS CLI v2 from a local macOS Terminal
- Disposable AWS account and a selected AWS Region
- CloudFormation and S3 permissions
- Public files contain placeholders only; no credentials, account IDs, private ARNs, or real bucket names

## Architecture and dependency order

```text
local YAML template
        │
        ▼
CloudFormation stack
        │
        ▼
S3 bucket
 ┌──────┼─────────┐
 │      │         │
versioning  encryption  Block Public Access
```

1. Configure and verify the CLI identity.
2. Generate a unique bucket name and save the values locally.
3. Create and validate the template.
4. Create the CloudFormation stack.
5. Wait for `CREATE_COMPLETE`.
6. Retrieve stack outputs and verify S3 state.
7. Upload and list a small test object.
8. Delete all object versions and delete markers, then delete the stack.
9. Verify AWS and local cleanup.

## Repository files

- [`template.yaml`](template.yaml) — parameterized CloudFormation template for the bucket.

## Implementation

### 1. Preflight and stable names

Use a dedicated CLI profile or another supported credential method. Do not place keys in the repository or in Terraform/CloudFormation files.

```bash
export AWS_PROFILE=YOUR_CLI_PROFILE
export AWS_REGION=YOUR_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"
export STACK_NAME=simple-s3-infrastructure
export BUCKET_NAME=my-infrastructure-bucket-unique123

aws sts get-caller-identity >/dev/null
aws configure get region --profile "$AWS_PROFILE"
```

Authentication proves which principal is operating the lab. It does not prove that the principal has every CloudFormation and S3 permission needed later.

### 2. Validate before deployment

```bash
aws cloudformation validate-template \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --template-body file://template.yaml \
  --query '{Description:Description,ParameterCount:length(Parameters),Capabilities:Capabilities}' \
  --output json
```

Expected shape:

```json
{
  "Description": "...",
  "ParameterCount": 1,
  "Capabilities": null
}
```

Validation checks template syntax and CloudFormation structure. It does not check bucket-name availability or deployment permissions.

### 3. Deploy and monitor

```bash
aws cloudformation create-stack \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name "$STACK_NAME" \
  --template-body file://template.yaml \
  --parameters "ParameterKey=BucketName,ParameterValue=$BUCKET_NAME"

aws cloudformation wait stack-create-complete \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name "$STACK_NAME"

aws cloudformation describe-stacks \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].StackStatus' \
  --output text
```

The final status must be `CREATE_COMPLETE`. The wait operation distinguishes an accepted asynchronous request from a completed deployment.

### 4. Retrieve outputs and verify S3

```bash
export CREATED_BUCKET="$({
  aws cloudformation describe-stacks \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue | [0]' \
    --output text
})"

aws s3api head-bucket \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --bucket "$CREATED_BUCKET"

aws s3api get-bucket-encryption \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --bucket "$CREATED_BUCKET" \
  --query 'ServerSideEncryptionConfiguration.Rules[0].{Algorithm:ApplyServerSideEncryptionByDefault.SSEAlgorithm,BucketKeyEnabled:BucketKeyEnabled}' \
  --output json

aws s3api get-bucket-versioning \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --bucket "$CREATED_BUCKET" \
  --query 'Status' \
  --output text

aws s3api get-public-access-block \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --bucket "$CREATED_BUCKET" \
  --query 'PublicAccessBlockConfiguration' \
  --output json
```

Expected configuration is `AES256`, `BucketKeyEnabled: true`, versioning `Enabled`, and all four public-access block values set to `true`.

### 5. Test normal object operations

```bash
printf 'Hello CloudFormation!\n' > test-file.txt
aws s3 cp test-file.txt "s3://$CREATED_BUCKET/test-file.txt" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"
aws s3 ls "s3://$CREATED_BUCKET/" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"
```

An upload and listing prove ordinary object operations. They do not prove that an object is publicly readable; public access remains blocked.

## Verification

The private CLI execution produced the following observed evidence:

| Check | Observed result |
| --- | --- |
| Template validation | Accepted; one parameter; no IAM capability required |
| Stack creation | `CREATE_COMPLETE` |
| Stack outputs | Two outputs; bucket-name output returned the created bucket |
| Bucket identity | `head-bucket` succeeded; Region matched the selected Region |
| Encryption | `AES256`; Bucket Key enabled |
| Versioning | `Enabled` |
| Public access | All four Block Public Access settings `true` |
| Functional test | Test object uploaded and listed successfully |
| Object cleanup | Version inventory and delete-marker inventory empty |
| AWS cleanup | Stack absent; exact bucket absent from inventory |
| Local cleanup | Template, test object, and local variables file removed |

The evidence proves this lab’s resources were created, verified, and removed. It does not prove that unrelated account resources are absent or that the billing console has already updated.

## Cost and safety

- CloudFormation has no separate charge, but S3 storage, requests, and transfer can incur charges while resources exist.
- Free Tier is not an absolute spending cap. Use a disposable account, avoid public access, and clean up immediately.
- Never commit access keys, secret keys, account IDs, private ARNs, state files, or real bucket names.
- Generate a unique bucket name once and preserve it across retries; S3 names use a global namespace.

## Cleanup

A versioned bucket needs special handling. `aws s3 rm --recursive` can leave historical versions behind, so enumerate and delete both versions and delete markers before deleting the stack.

```bash
aws s3api list-object-versions \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --bucket "$CREATED_BUCKET" \
  --output json

# Delete every returned object version and delete marker, then:
aws cloudformation delete-stack \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name "$STACK_NAME"

aws cloudformation wait stack-delete-complete \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name "$STACK_NAME"
```

Verify both the stack and exact bucket are absent. Remove local template, test, and variables files only after the cloud read-back is complete.

## What this lab teaches

- CloudFormation is declarative: the template describes the desired state and the service orchestrates creation.
- S3 bucket names are globally unique, while CloudFormation stacks are scoped to an account and Region.
- Validation, deployment, resource configuration, functional testing, and cleanup are separate evidence gates.
- Versioning improves recovery but changes cleanup requirements because historical versions must also be removed.
- The reusable IaC habit is to create from code, read the real state back, test the intended behavior, and delete what you created.
