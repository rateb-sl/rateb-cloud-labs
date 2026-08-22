# IAM permissions lab: permissions are inherited, not personal

## Goal

Build a small three-user IAM experiment that makes permission boundaries observable. Each user receives a different group policy and reaches a different authorization wall.

The design principle is simple: authentication identifies a principal; policies determine what that principal may do.

## Environment

- AWS account or training sandbox
- AWS Management Console
- Three temporary IAM users and groups
- No application resources required beyond the permission tests

## Authorization model

```text
User → Group membership → Group policy → Action/resource decision
```

A user with a valid password but no applicable policy still has no useful permissions. Explicit Deny overrides Allow; anything without a matching Allow is an implicit deny.

## Implementation

### 1. Define the permission matrix

| User | Group | Intended access |
|---|---|---|
| `s3-user` | `S3-ReadOnly` | Read/list S3 |
| `ec2-user` | `EC2-ReadOnly` | Describe EC2 |
| `admin-user` | `Admin` | Administrative test access |

The matrix is the desired state. It prevents permissions from being assigned by intuition while creating the experiment.

### 2. Create groups and attach policies

The policy examples are under [`policies/`](policies/). A statement has three primary decisions:

```json
{
  "Effect": "Allow",
  "Action": ["s3:ListBucket", "s3:GetObject"],
  "Resource": "*"
}
```

- `Effect` determines allow or deny.
- `Action` identifies the API operations.
- `Resource` identifies where they apply.

In a production design, scope resources more narrowly than `*` wherever the service and use case allow it.

### 3. Create users and assign exactly one group

Add each temporary user to the intended group only. Group inheritance keeps permission ownership manageable; direct user policies make review and change control harder as teams grow.

### 4. Verify behavior, not just membership

Sign in as each user and test the intended and denied surfaces:

- `s3-user`: S3 works; EC2 access is denied.
- `ec2-user`: EC2 read access works; S3 access is denied.
- `admin-user`: the administrative test works.

Membership proves the relationship exists. The actual console/API result proves authorization behavior.

## Failure boundaries

If a result is unexpected, inspect in this order:

1. Correct account and sign-in identity
2. Group membership
3. Attached policy and policy version
4. Action/resource scope
5. Explicit Deny or permissions boundary
6. Service/Region behavior

Do not solve every access problem by adding broader permissions.

## Cleanup

Delete the three temporary users and groups. Verify the names no longer appear in IAM. IAM users do not own the resources they accessed; deleting a user does not delete unrelated AWS resources.
