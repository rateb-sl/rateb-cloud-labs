# IAM permissions lab: permissions are inherited, not personal

## Goal

Understand how AWS IAM permissions actually work by building a small three-user experiment and watching each user hit a different permission wall.

The core lesson: an IAM user can do only what the policies attached to their user groups allow, nothing more. Permissions are inherited through group membership. A user who belongs to no group has no permissions, even with a valid password.

## Environment

- AWS account (a training sandbox or an account you control)
- AWS Management Console

## The three-user experiment

1. Create three IAM users: `s3-user`, `ec2-user`, and `admin-user`.
2. Create three groups: `S3-ReadOnly`, `EC2-ReadOnly`, `Admin`.
3. Attach a policy to each group (examples in [`policies/`](policies/)):
   - `S3-ReadOnly` gets S3 read access.
   - `EC2-ReadOnly` gets EC2 describe access.
   - `Admin` gets full access.
4. Add each user to exactly one group.
5. Sign in at the account alias URL (`https://<account-alias>.signin.aws.amazon.com/console`) as each user in turn.

Expected results:

| User | What they see | What they cannot do |
|---|---|---|
| `s3-user` | S3 buckets | Open EC2, change anything |
| `ec2-user` | EC2 instances (read-only) | Open S3, change anything |
| `admin-user` | Everything | Nothing, within the account |

## How a policy statement works

Every IAM policy is a list of statements. Each statement has three parts:

```json
{
  "Effect": "Allow",
  "Action": ["s3:ListBucket", "s3:GetObject"],
  "Resource": "*"
}
```

- `Effect`: `Allow` or `Deny`. An explicit Deny always wins over an Allow.
- `Action`: the API actions the statement covers.
- `Resource`: what the actions can be applied to.

Two rules make the whole system predictable:

- **Implicit deny**: anything not explicitly allowed is denied by default. A user with no policies can do nothing.
- **Least privilege**: grant the minimum actions needed for the job. Read-only groups are the safest starting point.

## Reading a policy correctly

When you look at a user's permissions, ask: what groups does this user belong to, and what policies do those groups carry? A policy attached directly to the user works the same way, but in practice groups are how teams stay manageable.

## Verification

- Sign in as `s3-user` and confirm S3 works and EC2 shows no access.
- Sign in as `ec2-user` and confirm the opposite.
- Confirm `admin-user` sees the full console.
- Check the account password policy if you want to enforce minimum length and rotation.

## Cleanup

Delete the three users and groups when the experiment is done. The users exist only in IAM; there are no other resources created by this lab.

## What this lab teaches

- Identity and permission are separate. Knowing who someone is tells you nothing until you read the attached policies.
- Group inheritance is the normal pattern; direct user policies are the exception.
- The most common support answer is not "give the user more access" but "find the group that owns the job and check its policy."
