# Remote S3 backend: share Terraform state without local files

## Goal

Configure Terraform to store state in Amazon S3 instead of a local `terraform.tfstate` file, migrate the state to a namespaced object key, and clean up without leaving cloud resources behind.

The transferable pattern is simple: create the state bucket outside Terraform, configure the backend with constants, initialize it, verify remote state, and treat migration as a copy that requires stale-object cleanup.

## Environment

- Terraform 1.15.x on macOS
- AWS CLI with an authenticated profile
- Disposable AWS test account
- Application resources in one AWS region
- State bucket in a separate AWS region

The real execution used a private bucket name and a private AWS profile. Those identifiers are intentionally omitted here.

## Design decisions

```text
manual S3 state bucket
        |
backend "s3" { bucket, key, region }
        |
terraform init
        |
remote state object
        |
key change + terraform init -migrate-state
        |
new state object + stale old object
        |
manual stale-object deletion
```

- The state bucket is created before Terraform uses the backend. Terraform cannot safely create the bucket that stores its own state.
- `bucket`, `key`, and `region` identify the S3 state location.
- The backend region identifies the state bucket. The provider region identifies where managed infrastructure is created; they do not have to match.
- `terraform init -migrate-state` copies state to the changed location. It does not delete the old object.
- Storage and locking are separate concerns. Plain S3 storage is not a complete concurrency-control design.

## Configuration example

The backend configuration cannot use input variables, so the example keeps the values as constants to be replaced before use.

[`providers.tf.example`](providers.tf.example) contains the Terraform and provider configuration. [`s3.tf`](s3.tf) contains a random suffix, an S3 bucket, and an output.

```hcl
backend "s3" {
  bucket = "<your-unique-state-bucket>"
  key    = "04-backend/state.tfstate"
  region = "<state-bucket-region>"
}
```

The application provider can use a different region:

```hcl
provider "aws" {
  region = "<application-region>"
}
```

Credentials are supplied by the AWS CLI profile or environment, never by Terraform configuration.

## Implementation sequence

### 1. Prepare a clean project

Copy the first Terraform project into a new working directory. Remove any existing local state and `.terraform/` directory before adding the backend.

```bash
cp -R 03-first-tf-project 04-backend
cd 04-backend
rm -f terraform.tfstate terraform.tfstate.backup
rm -rf .terraform
```

### 2. Create the state bucket manually

Create a unique S3 bucket with Block Public Access enabled. Record its actual region; that value must be used by the backend configuration.

### 3. Configure and initialize the backend

Replace the placeholders in `providers.tf.example`, save it as `providers.tf`, and initialize:

```bash
terraform init
```

Initialization configures the backend and installs the required providers. It does not prove that an application resource was created.

### 4. Plan and apply

```bash
terraform plan
terraform apply
```

The plan should show two additions: the random suffix and the application bucket. After apply, state should be written to S3 rather than to a local `terraform.tfstate` file.

### 5. Verify remote state

```bash
terraform state list
aws s3api head-object \
  --bucket <state-bucket> \
  --key terraform.tfstate \
  --region <state-bucket-region>
```

The state list proves Terraform tracks the resources. The S3 read proves the configured backend contains the state object. Neither check alone proves every cloud property is correct.

### 6. Migrate the state key

Change the backend key to a namespaced path and reinitialize:

```hcl
key = "04-backend/state.tfstate"
```

```bash
terraform init -migrate-state
```

Verify that both the old and new objects exist. Delete the stale old object manually, then verify only the new key remains.

### 7. Clean up in dependency order

Destroy managed resources before deleting the state bucket:

```bash
terraform destroy -auto-approve
terraform state list
```

The state list must be empty before removing the active state object and deleting the bucket. Deleting the backend first would remove Terraform’s source of truth before the managed resources were destroyed.

## Verification

Observed during the private execution:

| Check | Result |
| --- | --- |
| Terraform initialization | S3 backend configured successfully; AWS and Random providers installed |
| Plan | `2 to add, 0 to change, 0 to destroy` |
| Apply | Two resources added; no local `terraform.tfstate`; remote state object present |
| Migration | New namespaced object present; old object also present until manual deletion |
| Stale-state cleanup | Old object deleted; active migrated object remained |
| Destroy | Two Terraform-managed resources destroyed; state list empty before backend deletion |
| Final cleanup | Application bucket and backend bucket both verified deleted |

A provider-package read/checksum failure occurred during the first cleanup attempt. Re-running `terraform init` repaired the local provider installation, after which destroy and all cleanup checks succeeded.

## Cost and safety

- S3 state can contain sensitive infrastructure details. Keep the bucket private and never commit state files.
- The AWS Free Tier is not an absolute spending cap. Use a disposable account, avoid public access, and clean up immediately.
- Do not publish real bucket names, account IDs, ARNs with identifiers, credentials, private keys, or `.terraform/` contents.
- For production, evaluate versioning, encryption, least-privilege IAM, and a supported locking strategy before relying on the backend for team work.

## Cleanup

The cleanup contract is part of the lab:

1. Destroy Terraform-managed resources.
2. Verify `terraform state list` is empty.
3. Delete the active state object.
4. Delete the now-empty backend bucket.
5. Verify both buckets are absent.

## What this lab teaches

Remote state is not just a storage setting. It changes the operational boundary of Terraform: initialization becomes a backend decision, the state bucket must be bootstrapped outside Terraform, backend and provider regions have different meanings, and migration requires explicit stale-data cleanup. The reusable habit is to distinguish configuration, state, real cloud resources, and evidence for each layer.
