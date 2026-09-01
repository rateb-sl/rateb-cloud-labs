# S3 + CloudFront static website: build it with the AWS CLI

## Goal

Build and verify a static website using an Amazon S3 website endpoint as a CloudFront custom HTTP origin. The lab focuses on the request path and dependency order rather than a custom domain:

```text
S3 website bucket → public object read → CloudFront custom origin → HTTPS viewer URL
```

This is the direct AWS CLI implementation. It is intentionally separate from the Terraform implementation in the neighboring lab folder.

## Environment

- AWS CLI
- An authenticated IAM profile with permission to create and delete the lab resources
- Region selected explicitly for every regional operation
- No custom domain, ACM certificate, or Route 53 record

Do not place credentials, account IDs, ARNs containing real identifiers, or live resource names in this folder.

## Build logic

1. **Create the bucket.** S3 bucket names are globally unique, so the name must include a generated suffix. The bucket is the origin storage layer.
2. **Enable website hosting.** The index and error documents make S3 respond as a website endpoint rather than as an object API.
3. **Upload HTML objects.** The objects are the content that S3 and CloudFront will deliver.
4. **Allow only public object reads.** A public S3 website needs anonymous `s3:GetObject`; it does not need anonymous upload or delete access.
5. **Create CloudFront.** The S3 website endpoint is a custom HTTP origin. The origin uses HTTP because the S3 website endpoint is HTTP; viewers are redirected to HTTPS at CloudFront.
6. **Read state back and test from outside.** A successful create command is not proof that the website works. Test the origin and the CloudFront URL independently.

## Manual implementation

Use placeholders in the commands below and set the profile and region in the shell before running them:

```bash
export AWS_PROFILE='<profile>'
export AWS_REGION='<region>'
export LAB_BUCKET='<globally-unique-bucket-name>'
```

Create the bucket, configure the website, and upload the content:

```bash
aws s3api create-bucket \
  --bucket "$LAB_BUCKET" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"

aws s3api put-bucket-website \
  --bucket "$LAB_BUCKET" \
  --website-configuration '{"IndexDocument":{"Suffix":"index.html"},"ErrorDocument":{"Key":"error.html"}}'

aws s3 cp index.html "s3://$LAB_BUCKET/index.html" --content-type text/html
aws s3 cp error.html "s3://$LAB_BUCKET/error.html" --content-type text/html
```

Allow the bucket policy to take effect, then create a CloudFront distribution whose custom origin is the S3 website endpoint. Keep these values explicit:

- origin protocol policy: `http-only`
- viewer protocol policy: `redirect-to-https`
- default root object: `index.html`
- allowed and cached methods: `GET`, `HEAD`
- price class: `PriceClass_100`
- viewer certificate: CloudFront default certificate

The exact JSON shape is service-specific; inspect the resulting distribution rather than trusting a copied identifier.

## Verification

Read the S3 website configuration and object metadata back:

```bash
aws s3api get-bucket-website --bucket "$LAB_BUCKET" --region "$AWS_REGION"
aws s3api head-object --bucket "$LAB_BUCKET" --key index.html --region "$AWS_REGION"
```

Read the CloudFront configuration back by discovering the distribution from its domain or a lab tag. Confirm:

| Check | Expected evidence |
|---|---|
| S3 website | `index.html` and `error.html` configured |
| Object metadata | `ContentType` is `text/html` |
| CloudFront origin | S3 website endpoint, not the S3 REST endpoint |
| Origin protocol | `http-only` |
| Viewer protocol | `redirect-to-https` |
| HTTPS request | HTTP 200 and expected page content |
| HTTP request | HTTP 301 with an HTTPS `Location` header |

### Observed run

- S3 website configuration and HTML object metadata were read back successfully.
- The CloudFront HTTPS request returned HTTP 200 with the expected heading.
- The HTTP request returned HTTP 301 and redirected to HTTPS.
- The distribution used the regional S3 website endpoint and `http-only` origin access.

## Failure corrected during the run

The regional S3 website hostname was initially formed with the wrong separator. The working format in this region is:

```text
<bucket>.s3-website.<region>.amazonaws.com
```

The CloudFront distribution was corrected and then re-read before the public URL test.

## Cost and safety

S3 storage and requests were small at lab scale. CloudFront and data transfer can incur charges while the distribution exists. Public website hosting is a deliberate trade-off for this exercise; a production design would normally use a private S3 origin with Origin Access Control and would not expose the bucket directly.

## Cleanup

Delete the CloudFront distribution first: disable it, wait until AWS accepts deletion, then delete it. After the distribution is gone:

```bash
aws s3 rm "s3://$LAB_BUCKET" --recursive --region "$AWS_REGION"
aws s3api delete-bucket --bucket "$LAB_BUCKET" --region "$AWS_REGION"
```

Read both services back and confirm the distribution and bucket are absent. Cleanup is part of the lab because it closes the cost and ownership loop.

## What this lab teaches

- S3 website hosting and the S3 REST endpoint are different origins.
- CloudFront can terminate HTTPS for viewers while using HTTP to an S3 website origin.
- IAM authorization, S3 public-access blocking, website configuration, and CloudFront behavior are separate layers.
- Verification must follow the request path from origin to edge to viewer.
- A CLI run and a Terraform run can implement the same architecture while teaching different operational skills.
