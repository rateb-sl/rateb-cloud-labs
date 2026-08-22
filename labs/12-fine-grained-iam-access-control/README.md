# Fine-grained IAM access control: authorization from request context

## Goal

Build a controlled AWS authorization environment where access depends on the caller, requested action, target resource, and request context.

The implementation demonstrates four IAM condition patterns and three policy surfaces:

- time-based access
- source-IP restrictions
- tag-based attribute access control (ABAC)
- recent-MFA requirements
- IAM role trust policy
- S3 resource policy
- STS session scope-down policy

The important engineering result is a verifiable authorization model, not a collection of broad permissions.

## Environment

- AWS CLI v2 from a Mac terminal or AWS CloudShell
- Python 3 for generating and validating policy JSON
- Disposable AWS account
- Explicit AWS Region
- Temporary S3 bucket and CloudWatch log group
- Temporary IAM user and role
- No access keys or passwords created for the test user

All examples use placeholders such as `<account-id>`, `<bucket-name>`, and `<region>`. Replace them only in a disposable environment. Never commit account identifiers, credentials, private keys, or raw terminal output.

## Architecture

```text
Human/admin caller
      |
      +--> IAM: create principals, policies, attachments, simulations
      +--> S3: create/configure bucket and upload a test object
      +--> CloudWatch Logs: create/configure log group

Test user
  +-- business-hours policy
  +-- IP-restriction policy
  +-- tag-based ABAC policy
  +-- MFA-required policy

Test role
  +-- trust policy: who may assume it?
  +-- business-hours policy: what may it do?
  +-- optional STS scope-down: what may one session do at most?

S3 bucket
  +-- public-access block
  +-- default AES256 encryption
  +-- resource policy for role access and HTTPS-only transport
  +-- tagged object under Engineering/
```

## Authorization model

Every request is evaluated as:

```text
caller
  → action
  → resource
  → request context
  → applicable identity/resource/session policies
  → explicit deny check
  → decision
```

The policy surfaces answer different questions:

| Surface | Question | Implementation |
|---|---|---|
| Identity policy | What may the user or role do? | Four condition-based managed policies |
| Trust policy | Who may enter the role? | Test user + Region/IP conditions |
| Resource policy | What does the bucket accept? | Encrypted role uploads, role reads, HTTPS-only transport |
| Session policy | What may one temporary session do at most? | One CloudWatch log group |

An explicit Deny overrides an Allow. If no matching Allow exists, the result is an implicit deny.

## Implementation

### 1. Establish the target context

Before any mutation, confirm the account, Region, and caller:

```bash
AWS_REGION="$(aws configure get region)"
aws sts get-caller-identity --region "$AWS_REGION"
```

This prevents a correct command from creating resources in the wrong account or Region. The check proves caller identity and configuration; it does not prove that every required service permission exists.

### 2. Create a repeatable resource boundary

The setup derives one project prefix and uses it for every temporary resource:

```bash
PROJECT_NAME="finegrained-access-<timestamp>"
BUCKET_NAME="${PROJECT_NAME}-<account-id>-test-bucket"
LOG_GROUP_NAME="/aws/lambda/${PROJECT_NAME}"
```

The names are persisted locally so an interrupted run can resume without losing track of ownership. The design pattern is:

```text
stable inputs → deterministic names → repeatable operations → safe cleanup
```

Create the S3 bucket and log group, then apply guardrails immediately:

```bash
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws logs put-retention-policy \
  --log-group-name "$LOG_GROUP_NAME" \
  --retention-in-days 7
```

Resource existence is not the same as safe configuration. Each setting was read back before continuing.

### 3. Define policies at the correct resource scope

The policy documents are kept under [`policies/`](policies/). They are supporting implementation artifacts; the design decision for each one is documented here beside its role in the system.

#### Bucket and object ARN scope

S3 actions operate at different resource scopes:

```text
s3:ListBucket → arn:aws:s3:::<bucket-name>
s3:GetObject  → arn:aws:s3:::<bucket-name>/*
s3:PutObject  → arn:aws:s3:::<bucket-name>/*
```

Using the wrong ARN scope produces a policy that may be valid JSON but cannot express the intended permission.

#### Upload conditions belong to upload actions

The bucket policy separates writes from reads:

```json
{
  "Sid": "AllowTestRoleEncryptedWrites",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::<account-id>:role/<test-role-name>"
  },
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::<bucket-name>/*",
  "Condition": {
    "StringEquals": {
      "s3:x-amz-server-side-encryption": "AES256"
    }
  }
}
```

`GetObject` is a separate statement without an upload-header condition. Access Analyzer caught the original design when the encryption condition was combined with both `GetObject` and `PutObject`.

#### Conditional identity policies

The four managed policies each express one control:

- **Business hours:** `aws:CurrentTime` limits S3 access to a UTC demonstration window.
- **IP restriction:** an Allow covers documented test ranges; an explicit Deny blocks other non-service requests.
- **ABAC:** `aws:PrincipalTag/Department` must match `s3:ExistingObjectTag/Department`.
- **MFA:** reads are allowed without MFA; writes require MFA and an MFA age under 3,600 seconds.

The policy documents were generated with Python rather than unsafe shell substitution so IAM policy variables such as `${s3:ExistingObjectTag/Department}` remain literal.

### 4. Create principals before applying relationships

The temporary user was created without credentials and tagged:

```text
Department = Engineering
Project    = <project-name>
```

The temporary role was created with a one-hour maximum session and tagged:

```text
Department  = Engineering
Environment = Lab
```

The role trust policy and the role permission policy answer different questions:

```text
Trust policy     → who may assume the role?
Permission policy → what may the role do after assumption?
```

Managed policies were then attached to the user, and the business-hours policy was attached to the role. A policy that merely exists in IAM has no effect until it is attached or applied through the relevant resource/session surface.

### 5. Apply the S3 resource policy and create a controlled fixture

After the role existed, the resource policy was applied to the bucket. A single object was uploaded with explicit encryption and tags:

```bash
aws s3api put-object \
  --bucket "$BUCKET_NAME" \
  --key "Engineering/test-file.txt" \
  --body "$TEST_FILE" \
  --tagging "Department=Engineering&Project=${PROJECT_NAME}" \
  --server-side-encryption AES256
```

The object is a controlled fixture for policy evaluation. Its key, encryption state, and tags are known, so each test changes one request-context variable at a time.

### 6. Validate state and behavior separately

The implementation used several evidence layers:

| Layer | What it proves |
|---|---|
| JSON validation | The local file is syntactically valid JSON |
| Access Analyzer | AWS can interpret the policy semantics |
| `get`/`list`/`head` APIs | The requested AWS state exists and has the expected configuration |
| Policy simulator | A supplied principal/action/resource/context produces a decision |
| Live object read-back | The object exists with the expected encryption and tags |
| Cleanup read-back | Named resources are absent after deletion |

The observed simulator results were:

| Scenario | Result |
|---|---|
| Matching principal/object Department tags | `allowed` |
| Mismatched Department tags | `implicitDeny` |
| `PutObject` without MFA | `implicitDeny` |
| `PutObject` with MFA age of 1,800 seconds | `allowed` |
| Role `GetObject` inside the time window | `allowed` |
| Log write from an allowed test range | `allowed` |
| Log write from a non-approved range | `explicitDeny` |

The combined principal simulation and isolated custom-policy simulation were both necessary. The combined result shows what an identity experiences with all attached policies; the isolated result shows whether one policy expresses the intended rule without another Allow masking it.

## Cleanup

Cleanup removed:

1. Object data
2. Policy attachments
3. IAM user and role
4. Customer-managed policies
5. Bucket policy
6. S3 bucket
7. CloudWatch log group
8. Local lab directory and variables file

Final verification returned:

```text
S3 bucket deletion verified.
CloudWatch log-group deletion verified.
Full cleanup verification passed.
```

## Design corrections made during execution

- Split `GetObject` from `PutObject` because the encryption request condition applies to uploads.
- Removed the unsupported `s3:x-amz-meta-project` condition after Access Analyzer rejected it.
- Treated the trust-policy `MISSING_RESOURCE` validation result as a validator limitation for IAM role trust-policy grammar; successful role creation was the decisive AWS validation.
- Recovered from terminal-session loss by reloading the local manifest and rebuilding derived identifiers.
- Passed the actual JSON string to `simulate-custom-policy`; `--policy-input-list` does not interpret a `file://` path as the document content.

## Verification summary

- S3 public-access block: all four settings enabled
- S3 default encryption: AES256
- Bucket public-status evaluation: `IsPublic=false`
- Test object: 45 bytes, AES256, expected tags
- CloudWatch retention: 7 days
- Test user: four policy attachments, no access keys
- Test role: business-hours policy, one-hour maximum session
- Access Analyzer: zero findings for the corrected identity/session/bucket policy set
- Cleanup: all temporary AWS resources and local lab files absent

## Cost and safety

- No EC2, database, NAT gateway, public IPv4, or other compute resource was used.
- S3 and CloudWatch can still incur small charges if left behind.
- The temporary user had no access keys or password.
- TEST-NET ranges were used only as policy-simulation inputs, not as live access assumptions.
- Cleanup is part of the definition of done.

## Repository contents

```text
12-fine-grained-iam-access-control/
├── README.md
└── policies/
    ├── bucket-policy.json
    ├── business-hours-policy.json
    ├── ip-restriction-policy.json
    ├── mfa-required-policy.json
    ├── session-scope-down-policy.json
    ├── tag-based-policy.json
    └── trust-policy.json
```

The policy files are deployable examples with placeholders. The README explains the design, implementation, and verification path as a self-contained engineering record.
