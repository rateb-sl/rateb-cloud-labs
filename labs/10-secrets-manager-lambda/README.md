# Secrets Manager + Lambda: no more hardcoded credentials

## Goal

Stop putting database passwords and API keys in application code. Build the smallest working version of the pattern teams actually use: store the secret in AWS Secrets Manager, and let a Lambda function retrieve it at runtime through the AWS Parameters and Secrets Lambda Extension — with local caching, so the function does not call the Secrets Manager API on every request.

The core lesson: **the credential lives in a vault, not in the code.** The code holds only a name and an IAM permission.

## Architecture

```text
Lambda function
    │  code reads SECRET_NAME from env
    ▼
local extension (localhost:2773)   ← AWS Parameters and Secrets Lambda Extension (layer)
    │  cached lookup
    ▼
Secrets Manager  ← IAM policy allows secretsmanager:GetSecretValue on ONE secret ARN
    ▼
decrypted secret returned to the function at runtime
```

Dependency order of the lab:

1. IAM role for Lambda (trust policy + basic execution policy)
2. The secret in Secrets Manager (encrypted at rest by KMS)
3. A least-privilege IAM policy scoped to that one secret ARN
4. The Python function code
5. Deploy the function with the extension layer
6. Configure extension environment variables (caching on)
7. Invoke and verify the secret arrives

## Environment

- AWS account (training sandbox or an account you control)
- AWS CLI configured (`aws configure`), region e.g. `eu-central-1`
- Lambda console (only needed to add the extension layer — see step 5)

## Steps

### 1. Variables

```bash
export IAM_ROLE_NAME="lambda-secrets-role"
export SECRET_NAME="app/database-secret"
export LAMBDA_FUNCTION_NAME="secrets-demo"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
```

Run these in every new terminal window — shell variables do not survive restarts.

### 2. IAM role for Lambda

```bash
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name ${IAM_ROLE_NAME} \
  --assume-role-policy-document file://trust-policy.json

aws iam attach-role-policy \
  --role-name ${IAM_ROLE_NAME} \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

export LAMBDA_ROLE_ARN=$(aws iam get-role --role-name ${IAM_ROLE_NAME} --query 'Role.Arn' --output text)
```

### 3. The secret

```bash
aws secretsmanager create-secret \
  --name ${SECRET_NAME} \
  --description "Sample application secrets for Lambda demo" \
  --secret-string '{"database_host":"mydb.cluster-xyz.us-east-1.rds.amazonaws.com","database_port":"5432","database_name":"production","username":"appuser","password":"REPLACE-WITH-A-STRONG-RANDOM-VALUE"}'

export SECRET_ARN=$(aws secretsmanager describe-secret --secret-id ${SECRET_NAME} --query 'ARN' --output text)
```

### 4. Least-privilege policy for the secret

The policy in [`policies/secrets-policy.json`](policies/secrets-policy.json) allows only `secretsmanager:GetSecretValue` — and only on the one secret ARN. Create and attach it:

```bash
aws iam create-policy \
  --policy-name "SecretsAccess" \
  --policy-document file://secrets-policy.json

aws iam attach-role-policy \
  --role-name ${IAM_ROLE_NAME} \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SecretsAccess"
```

### 5. Function code + deploy

The handler in [`code/lambda_function.py`](code/lambda_function.py) calls the extension's local HTTP endpoint (`http://localhost:2773/secretsmanager/get?secretId=...`) with the session token as the auth header — no AWS SDK in the code, no hardcoded credentials.

```bash
mkdir -p lambda-package
cp code/lambda_function.py lambda-package/
cd lambda-package && zip -q -r ../lambda-function.zip . && cd ..

aws lambda create-function \
  --function-name ${LAMBDA_FUNCTION_NAME} \
  --runtime python3.12 \
  --role ${LAMBDA_ROLE_ARN} \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://lambda-function.zip \
  --timeout 30 \
  --memory-size 256 \
  --environment Variables="{SECRET_NAME=${SECRET_NAME}}"
```

**Add the extension layer (console):** the CLI cannot list this cross-account layer, so use the console: Lambda → your function → Configuration → Layers → Add a layer → **AWS layers** → search `AWS-Parameters-and-Secrets-Lambda-Extension` → latest version → Add. The console gives you the correct current ARN.

### 6. Extension configuration (caching on)

```bash
aws lambda update-function-configuration \
  --function-name ${LAMBDA_FUNCTION_NAME} \
  --environment Variables="{SECRET_NAME=${SECRET_NAME},PARAMETERS_SECRETS_EXTENSION_CACHE_ENABLED=true,PARAMETERS_SECRETS_EXTENSION_CACHE_SIZE=1000,PARAMETERS_SECRETS_EXTENSION_MAX_CONNECTIONS=3,PARAMETERS_SECRETS_EXTENSION_HTTP_PORT=2773}"

aws lambda wait function-updated-v2 --function-name ${LAMBDA_FUNCTION_NAME}
```

## Verification

Invoke the function and read the response — this proves the whole chain works:

```bash
aws lambda invoke \
  --function-name ${LAMBDA_FUNCTION_NAME} \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  response.json

cat response.json
```

Expected: HTTP 200 with the secret's fields (the password is deliberately not returned):

```json
{"statusCode": 200, "body": "{\"message\": \"Secret retrieved successfully\", \"database_host\": \"...\", \"database_name\": \"production\", \"username\": \"appuser\", \"extension_cache\": \"Enabled with 300s TTL\", \"note\": \"Password retrieved but not displayed for security\"}"}
```

Also verify by reading state back after each step: `aws iam list-attached-role-policies`, `aws secretsmanager describe-secret`, `aws lambda get-function`.

## Cost

- Secrets Manager: ~$0.40 per secret per month (not free tier).
- Lambda: per-invocation, negligible at this scale.
- **Cleanup is part of the lab** — delete everything when done.

## Cleanup

```bash
aws lambda delete-function --function-name ${LAMBDA_FUNCTION_NAME}

aws iam detach-role-policy --role-name ${IAM_ROLE_NAME} \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam detach-role-policy --role-name ${IAM_ROLE_NAME} \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SecretsAccess"
aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SecretsAccess"
aws iam delete-role --role-name ${IAM_ROLE_NAME}

aws secretsmanager delete-secret --secret-id ${SECRET_NAME} --force-delete-without-recovery

rm -rf lambda-package lambda-function.zip response.json trust-policy.json secrets-policy.json
```

Verify the account is back to start: all three list commands should come back empty.

```bash
aws lambda list-functions --query 'Functions[].FunctionName'
aws secretsmanager list-secrets --query 'SecretList[].Name'
aws iam list-roles --query 'Roles[?starts_with(RoleName, `lambda-secrets-role`)].RoleName'
```

## Lessons learned

- **The CLI cannot discover this cross-account layer.** `list-layer-versions` returns empty and `get-layer-version` returns "not found" — the console is the reliable source for the layer ARN, and hardcoded version numbers rot.
- **A heredoc that never closes eats your commands.** Paste heredoc blocks alone; `EOF` must sit on its own line; validate JSON files with `python3 -m json.tool` before sending them to AWS.
- **Empty shell variables create broken JSON.** `"Resource": ""` passes JSON validation but AWS rejects it — re-derive ARNs at the point of use and guard before writing files.
- **macOS zsh does not treat `#` as a comment in interactive mode** — `setopt INTERACTIVE_COMMENTS` silences the noise.
- **Authentication is not authorization.** A successful `aws sts get-caller-identity` proves you exist in the account; it does not prove the Lambda role can read the secret. Test the actual path (invoke).
