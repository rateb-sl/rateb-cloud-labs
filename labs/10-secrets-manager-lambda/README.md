# Secrets Manager and Lambda: keep credentials out of code

## Goal

Build a Lambda path where application credentials remain in Secrets Manager and the function retrieves them at runtime through the AWS Parameters and Secrets Lambda Extension.

The credential lives in a managed secret. The function contains only a secret name and the IAM permission required to read that one secret.

## Architecture

```text
Lambda function
  → local extension endpoint on localhost:2773
  → cached request to Secrets Manager
  → one secret ARN allowed by IAM
  → secret returned at runtime
```

The dependency order matters:

```text
Lambda trust role
→ secret
→ least-privilege GetSecretValue policy
→ function code
→ extension layer
→ cache configuration
→ invocation verification
```

## Implementation

### 1. Define names and account context

```bash
export IAM_ROLE_NAME="lambda-secrets-role"
export SECRET_NAME="app/database-secret"
export LAMBDA_FUNCTION_NAME="secrets-demo"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
```

Re-derive these values after a terminal restart. Do not hard-code credentials or real secret values in source control.

### 2. Create the Lambda trust role

The trust policy allows the Lambda service to assume the role. Attach the basic execution policy, then read the role ARN back. Trust and permission are separate surfaces.

### 3. Create the secret

```bash
aws secretsmanager create-secret \
  --name "$SECRET_NAME" \
  --description "Sample application secret" \
  --secret-string '<local disposable test JSON>'

SECRET_ARN="$(aws secretsmanager describe-secret \
  --secret-id "$SECRET_NAME" \
  --query ARN --output text)"
```

The secret value is intentionally not shown in this repository. The ARN is the resource boundary for the least-privilege policy.

### 4. Scope access to one secret

[`policies/secrets-policy.json`](policies/secrets-policy.json) grants only `secretsmanager:GetSecretValue` on the one secret ARN. Attach it to the Lambda role after verifying the ARN is non-empty.

A successful `get-caller-identity` proves the setup caller is authenticated; it does not prove the Lambda role can read the secret. The invocation is the end-to-end test.

### 5. Deploy the function and extension

[`code/lambda_function.py`](code/lambda_function.py) calls the extension's local endpoint with the Lambda session token. It does not contain an AWS access key or secret.

Package and deploy the function with the selected runtime and role. Add the current AWS Parameters and Secrets Lambda Extension layer through the supported console flow when the CLI cannot enumerate the cross-account layer.

### 6. Configure caching

Enable the extension cache through Lambda environment variables, then wait for the function configuration update before invoking it. Caching reduces repeated Secrets Manager calls but does not replace least-privilege IAM.

## Verification

```bash
aws lambda invoke \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  response.json

python3 -m json.tool response.json
```

The response should show a successful retrieval without returning the password. Read back the role attachments, secret metadata, function configuration, and invocation result.

## Failure boundaries

- A missing layer ARN is a discovery/version issue; do not hard-code a stale version.
- Empty shell variables can create an invalid empty resource ARN.
- A trust-policy success does not prove `GetSecretValue` authorization.
- Never print the secret value while debugging; inspect status, ARN, and redacted fields.

## Cleanup

Secrets Manager is chargeable per secret/month; Lambda is usage-based. Cleanup must delete the function, detach/delete the custom policy, delete the role, and delete the secret with the chosen recovery behavior. Verify the named function, secret, role, and policy are absent.
