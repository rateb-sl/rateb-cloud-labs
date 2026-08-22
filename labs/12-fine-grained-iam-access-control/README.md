# Fine-grained IAM access control: reason about requests, not just users

## Goal

Build a controlled AWS authorization experiment where access changes according to identity, resource, session, and request context.

The transferable lesson is not memorizing IAM JSON. It is learning to answer, for every request:

```text
Who is calling?
What action are they requesting?
Which resource does that action target?
What context is present?
Which policy layers apply?
What evidence proves the decision?
```

This lab uses a temporary S3 bucket, a CloudWatch log group, a tagged IAM user, a tagged IAM role, condition-based policies, an S3 resource policy, and IAM policy simulation.

## Environment

- AWS CLI v2 on macOS or AWS CloudShell
- Python 3 for local JSON generation and validation
- A disposable AWS account or sandbox
- An explicitly configured AWS Region
- An administrator or delegated operator identity for setup and cleanup
- No access keys or passwords created for the temporary test user

The examples use placeholders. Replace them locally; do not commit account IDs, ARNs with real identifiers, credentials, private keys, or raw terminal output.

## Architecture and mental model

```text
Human/admin CLI identity
        |
        +--> IAM: create principals, policies, attachments, simulations
        +--> S3: create/configure bucket, upload controlled object
        +--> CloudWatch Logs: create/configure log group

Temporary IAM user
  +-- business-hours policy
  +-- IP-restriction policy
  +-- tag-based ABAC policy
  +-- MFA-required policy

Temporary IAM role
  +-- trust policy: who may assume it?
  +-- business-hours permission policy: what may it do?
  +-- optional STS scope-down: what may this session do at most?

S3 bucket
  +-- public-access block
  +-- default AES256 encryption
  +-- resource policy: encrypted role writes, role reads, HTTPS-only transport
  +-- tagged test object
```

A useful AWS infrastructure lifecycle is:

```text
discover context
→ define desired state
→ identify dependencies and blast radius
→ create the smallest foundation
→ apply guardrails
→ connect identities, policies, and resources
→ verify state and behavior separately
→ test failure paths
→ measure cost
→ clean up in reverse dependency order
```

## Policy layers

| Layer | Question | This lab's example |
|---|---|---|
| Identity policy | What may this user or role do? | Time, IP, tag, and MFA policies |
| Trust policy | Who may assume this role? | The temporary test user with Region/IP conditions |
| Resource policy | What does the bucket accept? | Encrypted role uploads and secure transport |
| Session policy | What may one temporary session do at most? | CloudWatch Logs for one log group |
| Request context | Under what conditions? | Time, IP, MFA, tags, transport |
| Explicit Deny | What must be blocked regardless of other Allows? | Non-approved IPs and insecure transport |

An explicit Deny overrides an Allow. If no matching Allow exists, the result is an implicit deny.

## Build sequence: what each stage is for

### 1. Confirm the target context

Verify the Region, account, and caller before any mutation. A correct command pointed at the wrong account is still a failed operation.

**Evidence limit:** identity and Region checks prove the target context, not every required permission.

### 2. Create a durable local manifest

Persist stable inputs such as the project name, Region, resource names, test time, and local policy directory. This makes reruns and cleanup deterministic.

**Design principle:** persist stable inputs; derive calculated ARNs and names when a shell starts.

### 3. Create and secure the foundation

Create the S3 bucket and CloudWatch log group, then immediately apply:

- S3 public-access block
- S3 default AES256 encryption
- Seven-day CloudWatch retention

Resource existence is not the same as safe configuration. Read each setting back after writing it.

### 4. Define policies as separate, testable ideas

Generate separate documents for:

- Business-hours access
- Source-IP restrictions
- Tag-based ABAC
- Recent-MFA writes
- Role trust
- S3 bucket resource policy
- STS session scope-down

For every statement, identify the principal, action, resource, condition, and expected failure mode.

The S3 ARN distinction is fundamental:

```text
s3:ListBucket → arn:aws:s3:::<bucket-name>
s3:GetObject  → arn:aws:s3:::<bucket-name>/*
```

### 5. Create principals and attributes

Create a temporary user without credentials and a temporary role with a one-hour maximum session. Add tags such as `Department=Engineering`.

Identity and permission are separate. A principal can exist without being able to perform any useful action.

### 6. Attach policies in dependency order

Create managed policies, attach the four identity policies to the user, and attach the business-hours permission policy to the role. Apply the bucket resource policy only after the role exists.

This is a dependency graph, not merely a list of commands:

```text
principal → policy → attachment → resource relationship
```

### 7. Create one controlled fixture

Upload one object at `Engineering/test-file.txt` with AES256 encryption and `Department=Engineering` plus a project tag.

A small known fixture makes policy behavior observable and cleanup predictable.

### 8. Test in isolation and in combination

Use principal simulation to see what the complete identity experiences. Use custom-policy simulation to test one policy's logic without unrelated Allows masking the result.

The two tests answer different questions:

```text
Combined simulation: what would this identity experience?
Isolated simulation: does this policy express the intended rule?
```

### 9. Test both success and failure paths

The observed decision matrix was:

| Test | Observed result | Reason |
|---|---|---|
| Matching principal/object tags | `allowed` | ABAC condition matched |
| Mismatched tags | `implicitDeny` | No tag-based Allow matched |
| MFA absent for `PutObject` | `implicitDeny` | MFA condition failed |
| MFA present and 1,800 seconds old | `allowed` | Both MFA conditions matched |
| Role `GetObject` inside business hours | `allowed` | Time condition matched |
| Allowed source IP | `allowed` | Allow matched and Deny did not |
| Disallowed source IP | `explicitDeny` | Explicit Deny matched |

Predict the result before running the simulator. That is the judgment skill.

### 10. Clean up in reverse dependency order

Remove object data, policy attachments, principals, managed policies, resource policies, buckets, log groups, and local files. Verify absence directly. A success message is not cleanup evidence.

## Verification

The real execution verified:

- S3 public-access block: all four settings `true`
- S3 default encryption: `AES256`
- S3 public-status evaluation: `IsPublic=false`
- Test object: 45 bytes, AES256, expected tags
- CloudWatch retention: 7 days
- Test user: four attached policies, no access keys
- Test role: business-hours policy, one-hour maximum session
- Access Analyzer: zero findings for the corrected identity/session/bucket policy set
- Cleanup: IAM principals/policies, object, bucket, log group, and local files absent

## Failure lessons

### Valid JSON is not a valid policy

Access Analyzer caught that an upload encryption condition had been combined with `GetObject`. Upload request conditions belong on `PutObject`; reads need a separate statement.

### Do not invent service condition keys

The attempted `s3:x-amz-meta-project` condition was rejected as an invalid S3 condition key and was removed. Verify service-specific condition keys against AWS documentation rather than assuming every HTTP header becomes an IAM key.

### Combined tests can hide the policy you intended to test

The user simulation returned `allowed` for a matching read, but another attached policy could also allow reads. Isolated custom-policy simulation proved the ABAC behavior itself.

### Shell state is part of reliability

Closing the terminal removes exported variables. Reload the saved manifest and rebuild derived ARNs before continuing. Never trust a trailing success message after an earlier command failed.

### Redaction belongs in shared output, not executable commands

Run the real local resource name, then mask identifiers when sharing output. Replacing a key or variable with `***` changes the command and can create a false 404 or parse error.

## Cost and safety

- No compute, database, NAT gateway, or public IP was used.
- S3 and CloudWatch resources can still incur small charges if left behind.
- The test user had no access keys.
- The source IP ranges were documentation-only TEST-NET ranges and were used for simulation, not live access.
- Cleanup and absence verification are part of the lab's definition of done.

## What this lab teaches

- IAM is request evaluation, not a list of names.
- Identity, trust, resource, and session policies answer different questions.
- Conditions turn broad permissions into context-aware controls.
- Least privilege depends on correct action/resource scope, not only narrow action names.
- Explicit Deny is a safety boundary; implicit deny is the default absence of permission.
- A strong lab proves state, behavior, failure paths, and cleanup.
- AI can generate syntax, but the engineer must choose the model, dependencies, safety boundaries, tests, and interpretation.

## Interview questions

1. What is the difference between an identity policy, a trust policy, and a resource policy?
2. Why does `s3:ListBucket` use the bucket ARN while `s3:GetObject` uses an object ARN?
3. How do implicit and explicit denies differ?
4. How did you isolate the ABAC policy from the user's other policies?
5. Why did the MFA test require both presence and age?
6. Why can valid JSON still be semantically wrong?
7. What dependency required the role to exist before applying the bucket policy?
8. What evidence proves cleanup rather than merely suggesting it?

## 60-second interview answer

> I built a temporary fine-grained IAM environment around a private encrypted S3 bucket and a CloudWatch log group. I created a tagged test user, a role with conditional trust, four identity policies for time, IP, tags, and MFA, plus an S3 resource policy and an STS scope-down document. I verified the state by reading IAM, S3, and CloudWatch back, then tested both isolated policies and the combined identity with explicit request context. Matching tags and recent MFA were allowed, mismatched tags and missing MFA produced implicit denies, and an unapproved source IP produced an explicit deny. Access Analyzer also exposed and helped correct an invalid S3 condition. Finally, I removed the resources and verified their absence.

## Cleanup

Use the same project-specific cleanup process that created the lab. Delete data before the bucket, detach policies before deleting principals, delete policies after detachment, and read the AWS state back until every named resource is absent.

## Portfolio boundary

This README is a sanitized learning artifact. Replace placeholders locally when experimenting, but never commit account IDs, real ARNs, credentials, private keys, personal IPs, or raw course material.
