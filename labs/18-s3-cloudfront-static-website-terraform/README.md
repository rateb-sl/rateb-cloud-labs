# S3 + CloudFront static website: manage the stack with Terraform

## Goal

Manage the same reduced static-website architecture declaratively:

```text
Terraform → S3 website bucket → CloudFront custom HTTP origin → HTTPS viewer URL
```

Terraform owns the bucket, website behavior, public-read policy, HTML objects, and CloudFront distribution. This is intentionally separate from the direct AWS CLI implementation in the neighboring lab folder.

## Environment

- Terraform 1.x
- HashiCorp AWS provider 5.x
- HashiCorp Random provider 3.x
- An authenticated AWS profile supplied through the normal AWS credential chain
- Region selected through `aws_region`
- No custom domain, ACM certificate, or Route 53 record

Do not commit `.terraform/`, state files, credentials, account IDs, or live identifiers.

## Why the resources are ordered this way

- The random suffix makes the S3 bucket name globally unique.
- The S3 website configuration establishes index and error behavior.
- The public-access-block resource is set to false because a public S3 website requires a bucket policy to be evaluated.
- The bucket policy grants only anonymous `s3:GetObject` on objects.
- The HTML objects must exist before CloudFront is created so the origin can be tested immediately.
- CloudFront uses the S3 **website endpoint** as a custom HTTP origin. It redirects viewers to HTTPS while using HTTP to the origin.
- Terraform's dependency graph destroys CloudFront before the origin resources, then removes the bucket objects and bucket.

## Run

```bash
export AWS_PROFILE='<profile>'
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output website_url
```

Review the plan before applying. The reduced configuration creates eight resources and no ACM or Route 53 resources.

## Verification

Read Terraform state back:

```bash
terraform state list
terraform output bucket_name
terraform output s3_website_endpoint
terraform output cloudfront_domain_name
```

Test both sides of the viewer protocol:

```bash
URL="$(terraform output -raw website_url)"
CF_DOMAIN="$(terraform output -raw cloudfront_domain_name)"
curl -fsS "$URL"
curl -sS -I "http://$CF_DOMAIN/"
```

| Check | Expected evidence |
|---|---|
| Terraform validation | Configuration is valid |
| State | Eight expected resources are tracked |
| HTTPS request | HTTP 200 and expected page heading |
| HTTP request | HTTP 301 with an HTTPS `Location` header |
| Origin behavior | S3 website endpoint with `http-only` origin policy |

### Observed run

- Terraform initialized with AWS provider 5.100.0 and Random provider 3.9.0.
- Validation passed.
- The saved plan contained eight resources to add.
- Apply completed with eight resources added and no changes or destructions.
- Terraform state listed the eight expected resources.
- HTTPS returned HTTP 200 with the expected Terraform page heading.
- HTTP returned HTTP 301 to HTTPS.

## Cost and safety

The bucket and CloudFront distribution can incur AWS charges while they exist. The public S3 website setting is intentionally limited to this no-domain exercise. For production, prefer a private bucket with CloudFront Origin Access Control, a custom certificate, and DNS managed separately.

## Cleanup

Destroy the tracked stack after verification:

```bash
terraform destroy
terraform state list
```

### Observed cleanup

- Terraform destroyed all eight managed resources.
- Terraform state was empty after destruction.
- Independent AWS checks found no matching S3 bucket and no matching CloudFront origin.

Cleanup is part of the Terraform workflow because state and real resources must agree.

## What this lab teaches

- Terraform turns a multi-service dependency chain into a repeatable state-managed configuration.
- `plan` is the review boundary; `apply` changes AWS; state and service read-backs are separate verification layers.
- Explicit dependencies matter when an edge service relies on an origin and its content.
- Declarative management does not remove the need to understand AWS request paths, permissions, regions, and cleanup.
