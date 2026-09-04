# API Gateway + DynamoDB URL shortener: verify the wiring, not just the resources

## Goal

Build a small serverless URL-shortening service:

```text
POST /                         GET /{shortCode}
    │                                  │
    ▼                                  ▼
API Gateway ──▶ create Lambda   API Gateway ──▶ redirect Lambda
                         │                         │
                         └──────────┬──────────────┘
                                    ▼
                              DynamoDB table
```

A `POST` request stores an original URL under a generated six-character code. A `GET` request looks up that code and returns an HTTP `302` response with a `Location` header.

The transferable pattern is **public request → managed gateway → least-privilege function → durable lookup → explicit HTTP response**. The main lesson is that creating each resource is not enough: methods, integrations, invoke permissions, deployments, and data-path behavior all need separate verification.

This is a deliberately small learning artifact, not a production URL-shortening service.

## Environment

- AWS CLI v2 from a local Mac Terminal
- Personal disposable AWS account
- Region `eu-central-1`
- API Gateway REST API
- AWS Lambda with Python `3.12`
- DynamoDB with on-demand billing
- No EC2 instance or SSH connection

The public artifact contains placeholders and generic names only. It does not contain account IDs, real ARNs, API identifiers, credentials, private URLs, or private command output.

## Architecture and dependency order

The two routes have different contracts:

| Method | Path | Lambda responsibility | DynamoDB operation | Response |
|---|---|---|---|---|
| `POST` | `/` | Generate a code and store the URL | `PutItem` | `200` plus `shortCode` |
| `GET` | `/{shortCode}` | Find the URL and redirect | `GetItem` | `302` plus `Location`, or `404` |

Build in this order:

1. Create the DynamoDB table.
2. Create a Lambda execution role with only the required DynamoDB actions and basic log permissions.
3. Package and create the two Lambda functions.
4. Create API Gateway resources and methods.
5. Grant API Gateway permission to invoke each function.
6. Configure the two `AWS_PROXY` integrations.
7. Deploy the REST API to a stage.
8. Test the success and not-found paths.
9. Delete every lab resource and read the state back.

An API Gateway method without an integration is only a route definition. An integration without a deployment is not available through the stage URL. A Lambda permission without the matching source ARN is not a complete trigger relationship.

## Implementation

The commands below are a sanitized reference path. Use a disposable account, set every variable explicitly, and inspect names before changing AWS state.

### 1. Establish the context

```bash
set -euo pipefail

export AWS_REGION="eu-central-1"
export AWS_DEFAULT_REGION="$AWS_REGION"
export TABLE_NAME="url-shortener-lab"
export ROLE_NAME="url-shortener-lambda-role"
export CREATE_FUNCTION_NAME="url-shortener-create"
export REDIRECT_FUNCTION_NAME="url-shortener-redirect"

aws --version
aws sts get-caller-identity --query '{Account:Account,Arn:Arn}' --output json
```

The identity check proves which principal is operating the lab. It does not prove that the principal has every later permission.

### 2. Create the table

```bash
aws dynamodb create-table \
  --region "$AWS_REGION" \
  --table-name "$TABLE_NAME" \
  --attribute-definitions AttributeName=shortCode,AttributeType=S \
  --key-schema AttributeName=shortCode,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --tags Key=Project,Value=URLShortenerLab

aws dynamodb wait table-exists \
  --region "$AWS_REGION" \
  --table-name "$TABLE_NAME"

aws dynamodb describe-table \
  --region "$AWS_REGION" \
  --table-name "$TABLE_NAME" \
  --query 'Table.{Name:TableName,Status:TableStatus,KeySchema:KeySchema,Billing:BillingModeSummary.BillingMode}' \
  --output table
```

Expected evidence is `ACTIVE`, a single hash key named `shortCode`, and on-demand billing. A successful create response alone does not prove that the table is ready.

### 3. Create the Lambda role and policy

The trust policy answers **who may assume the role**. The permissions policy answers **what the function may do after assuming it**.

```bash
cat > /tmp/url-shortener-trust-policy.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
TABLE_ARN="arn:aws:dynamodb:${AWS_REGION}:${ACCOUNT_ID}:table/${TABLE_NAME}"

aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file:///tmp/url-shortener-trust-policy.json

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

cat > /tmp/url-shortener-dynamodb-policy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["dynamodb:GetItem", "dynamodb:PutItem"],
      "Resource": "$TABLE_ARN"
    }
  ]
}
JSON

POLICY_ARN="$(aws iam create-policy \
  --policy-name "${ROLE_NAME}-dynamodb-policy" \
  --policy-document file:///tmp/url-shortener-dynamodb-policy.json \
  --query 'Policy.Arn' \
  --output text)"

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "$POLICY_ARN"

aws iam list-attached-role-policies \
  --role-name "$ROLE_NAME" \
  --query 'AttachedPolicies[].PolicyName' \
  --output table
```

The live run caught an important partial-state failure: the custom policy existed but was not initially attached. The role was usable only after the attachment was read back and confirmed.

### 4. Package and create the Lambda functions

The reference handlers are in [`lambda/create_function.py`](lambda/create_function.py) and [`lambda/redirect_function.py`). They use the `TABLE_NAME` environment variable rather than embedding an account-specific table name.

```bash
ROLE_ARN="$(aws iam get-role \
  --role-name "$ROLE_NAME" \
  --query 'Role.Arn' \
  --output text)"

zip -q -j /tmp/url-shortener-create.zip lambda/create_function.py
zip -q -j /tmp/url-shortener-redirect.zip lambda/redirect_function.py

aws lambda create-function \
  --region "$AWS_REGION" \
  --function-name "$CREATE_FUNCTION_NAME" \
  --runtime python3.12 \
  --role "$ROLE_ARN" \
  --handler create_function.lambda_handler \
  --environment "Variables={TABLE_NAME=$TABLE_NAME}" \
  --zip-file fileb:///tmp/url-shortener-create.zip

aws lambda create-function \
  --region "$AWS_REGION" \
  --function-name "$REDIRECT_FUNCTION_NAME" \
  --runtime python3.12 \
  --role "$ROLE_ARN" \
  --handler redirect_function.lambda_handler \
  --environment "Variables={TABLE_NAME=$TABLE_NAME}" \
  --zip-file fileb:///tmp/url-shortener-redirect.zip

aws lambda get-function-configuration \
  --region "$AWS_REGION" \
  --function-name "$CREATE_FUNCTION_NAME" \
  --query '{Name:FunctionName,Runtime:Runtime,Handler:Handler,State:State,LastUpdate:LastUpdateStatus}' \
  --output table

aws lambda get-function-configuration \
  --region "$AWS_REGION" \
  --function-name "$REDIRECT_FUNCTION_NAME" \
  --query '{Name:FunctionName,Runtime:Runtime,Handler:Handler,State:State,LastUpdate:LastUpdateStatus}' \
  --output table
```

`Active` and `LastUpdateStatus: Successful` prove that Lambda accepted the package and configuration. They do not prove that API Gateway can invoke the functions or that DynamoDB access works at runtime.

### 5. Create API Gateway routes

```bash
API_ID="$(aws apigateway create-rest-api \
  --region "$AWS_REGION" \
  --name "${TABLE_NAME}-api" \
  --query 'id' \
  --output text)"

ROOT_RESOURCE_ID="$(aws apigateway get-resources \
  --region "$AWS_REGION" \
  --rest-api-id "$API_ID" \
  --query 'items[?path==`/`].id | [0]' \
  --output text)"

SHORT_CODE_RESOURCE_ID="$(aws apigateway create-resource \
  --region "$AWS_REGION" \
  --rest-api-id "$API_ID" \
  --parent-id "$ROOT_RESOURCE_ID" \
  --path-part '{shortCode}' \
  --query 'id' \
  --output text)"

aws apigateway put-method \
  --region "$AWS_REGION" \
  --rest-api-id "$API_ID" \
  --resource-id "$ROOT_RESOURCE_ID" \
  --http-method POST \
  --authorization-type NONE

aws apigateway put-method \
  --region "$AWS_REGION" \
  --rest-api-id "$API_ID" \
  --resource-id "$SHORT_CODE_RESOURCE_ID" \
  --http-method GET \
  --authorization-type NONE

aws apigateway get-resources \
  --region "$AWS_REGION" \
  --rest-api-id "$API_ID" \
  --query 'items[].{Path:path,Methods:resourceMethods}' \
  --output table
```

Expected evidence is `POST` on `/` and `GET` on `/{shortCode}`. Quoting `{shortCode}` avoids shell brace expansion and makes the intended path explicit.

### 6. Grant invoke permissions and configure integrations

API Gateway needs a resource-based permission on each Lambda. Quote source ARNs containing `*`; otherwise zsh may try to expand the wildcard locally.

```bash
CREATE_LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${CREATE_FUNCTION_NAME}"
REDIRECT_LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${REDIRECT_FUNCTION_NAME}"

aws lambda add-permission \
  --region "$AWS_REGION" \
  --function-name "$CREATE_FUNCTION_NAME" \
  --statement-id apigateway-create \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:${ACCOUNT_ID}:${API_ID}/*/POST/"

aws lambda add-permission \
  --region "$AWS_REGION" \
  --function-name "$REDIRECT_FUNCTION_NAME" \
  --statement-id apigateway-redirect \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:${ACCOUNT_ID}:${API_ID}/*/GET/{shortCode}"

aws apigateway put-integration \
  --region "$AWS_REGION" \
  --rest-api-id "$API_ID" \
  --resource-id "$ROOT_RESOURCE_ID" \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${CREATE_LAMBDA_ARN}/invocations"

aws apigateway put-integration \
  --region "$AWS_REGION" \
  --rest-api-id "$API_ID" \
  --resource-id "$SHORT_CODE_RESOURCE_ID" \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${REDIRECT_LAMBDA_ARN}/invocations"
```

`AWS_PROXY` passes the request to Lambda and maps Lambda's response back to HTTP. It is why the create function receives `event.body`, the redirect function receives `event.pathParameters.shortCode`, and the returned `statusCode`/headers become the API response.

Read the integrations back before deploying:

```bash
aws apigateway get-integration \
  --region "$AWS_REGION" \
  --rest-api-id "$API_ID" \
  --resource-id "$ROOT_RESOURCE_ID" \
  --http-method POST \
  --query '{Type:type,Method:httpMethod,Uri:uri}' \
  --output table

aws apigateway get-integration \
  --region "$AWS_REGION" \
  --rest-api-id "$API_ID" \
  --resource-id "$SHORT_CODE_RESOURCE_ID" \
  --http-method GET \
  --query '{Type:type,Method:httpMethod,Uri:uri}' \
  --output table
```

### 7. Deploy a stage

```bash
aws apigateway create-deployment \
  --region "$AWS_REGION" \
  --rest-api-id "$API_ID" \
  --stage-name dev \
  --description "URL shortener lab deployment"

aws apigateway get-stage \
  --region "$AWS_REGION" \
  --rest-api-id "$API_ID" \
  --stage-name dev \
  --query '{Stage:stageName,Deployment:deploymentId}' \
  --output table
```

The stage URL follows this form:

```text
https://<api-id>.execute-api.<region>.amazonaws.com/dev
```

A deployment snapshots the current API configuration. Later method or integration changes require another deployment before the stage sees them.

## Verification

Use the stage URL from the deployment, not a placeholder URL:

```bash
API_BASE_URL="https://<api-id>.execute-api.<region>.amazonaws.com/dev"

curl -i -sS \
  -X POST \
  "${API_BASE_URL}/" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com/reference-page"}'
```

Expected result:

```text
HTTP/2 200

{"shortCode": "<six-character-code>"}
```

Read the generated code back from DynamoDB before testing the redirect:

```bash
SHORT_CODE="<six-character-code>"

aws dynamodb get-item \
  --region "$AWS_REGION" \
  --table-name "$TABLE_NAME" \
  --key "{\"shortCode\":{\"S\":\"$SHORT_CODE\"}}" \
  --projection-expression 'shortCode, originalUrl' \
  --output json
```

Then test both redirect branches:

```bash
curl -i -sS \
  "${API_BASE_URL}/${SHORT_CODE}"
```

Expected success path:

```text
HTTP/2 302
location: https://example.com/reference-page
```

```bash
curl -i -sS \
  "${API_BASE_URL}/does-not-exist"
```

Expected not-found path:

```text
HTTP/2 404

{"error": "Not found"}
```

### Observed live-run evidence

The live run in `eu-central-1` produced:

| Check | Observed result | What it proves |
|---|---|---|
| DynamoDB table | `ACTIVE`, hash key `shortCode` | Storage dependency was ready |
| Lambda functions | Both `python3.12`, `Active`, update successful | Code packages and roles were accepted |
| API methods | `POST /`, `GET /{shortCode}` | Route model was present |
| Integrations | Both `AWS_PROXY`, correct Lambda targets | Methods were connected to functions |
| Deployment | `dev` stage created | The route configuration was published |
| Create request | HTTP `200`, six-character code returned | Gateway → Lambda → DynamoDB write path worked |
| Redirect request | HTTP `302`, `Location` header returned | Gateway → Lambda → DynamoDB read path worked |
| Unknown code | HTTP `404`, `Not found` body | Negative lookup path worked |
| Cleanup | APIs, functions, log groups, IAM resources, and table absent | The disposable lab boundary was removed |

The exact live API ID, account ID, generated code, and endpoint are intentionally omitted.

## Failure modes and corrections

### Resource exists but is not connected

`EntityAlreadyExists` or `ResourceConflictException` is a state signal, not proof that the existing resource is correct. Read back the role attachments, Lambda configuration, API methods, integrations, and invoke policies before continuing.

### zsh wildcard expansion

An unquoted source ARN containing `*` can fail locally with `zsh: no matches found`. Quote the complete ARN:

```bash
--source-arn "arn:aws:execute-api:${AWS_REGION}:${ACCOUNT_ID}:${API_ID}/*/POST/"
```

### Literal placeholders

Never paste `<api-id>` or `<resource-id>` into zsh. Angle brackets are shell redirection syntax. Substitute the actual value returned by the preceding command, or use a variable as in the implementation above.

### Local file content versus shell commands

Python code belongs inside a file before it is zipped. Pasting Python directly into zsh produces a shell parse error; it does not create a Lambda package.

## Cost and safety

- DynamoDB uses `PAY_PER_REQUEST`, so there is no provisioned-capacity commitment.
- Lambda, API Gateway, and small DynamoDB tests are low-volume, but Free Tier eligibility and pricing vary by account.
- The API uses `authorization-type NONE` for learning simplicity. Do not expose sensitive data through this pattern.
- The create handler accepts only HTTP(S) URLs in the reference code, but it does not implement authentication, abuse prevention, rate limiting, quotas, or URL reputation checks.
- Generated short codes use random UUID characters and do not handle collision retries or custom aliases.
- Delete test resources immediately after validation and confirm absence with service-specific read-backs.

## Cleanup

Cleanup is part of the lab, not an optional afterthought. Delete in dependency-safe order:

```bash
set -euo pipefail

# Set these from the same run; do not use identifiers from another API.
export AWS_REGION="eu-central-1"
export TABLE_NAME="url-shortener-lab"
export ROLE_NAME="url-shortener-lambda-role"
export CREATE_FUNCTION_NAME="url-shortener-create"
export REDIRECT_FUNCTION_NAME="url-shortener-redirect"
export API_ID="<api-id>"

aws apigateway delete-rest-api \
  --region "$AWS_REGION" \
  --rest-api-id "$API_ID"

aws lambda delete-function \
  --region "$AWS_REGION" \
  --function-name "$CREATE_FUNCTION_NAME"
aws lambda delete-function \
  --region "$AWS_REGION" \
  --function-name "$REDIRECT_FUNCTION_NAME"

aws logs delete-log-group \
  --region "$AWS_REGION" \
  --log-group-name "/aws/lambda/$CREATE_FUNCTION_NAME" || true
aws logs delete-log-group \
  --region "$AWS_REGION" \
  --log-group-name "/aws/lambda/$REDIRECT_FUNCTION_NAME" || true

CUSTOM_POLICY_ARN="$(aws iam list-policies \
  --scope Local \
  --query "Policies[?PolicyName=='${ROLE_NAME}-dynamodb-policy'].Arn | [0]" \
  --output text)"

aws iam detach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam detach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "$CUSTOM_POLICY_ARN"
aws iam delete-policy --policy-arn "$CUSTOM_POLICY_ARN"
aws iam delete-role --role-name "$ROLE_NAME"

aws dynamodb delete-table \
  --region "$AWS_REGION" \
  --table-name "$TABLE_NAME"
aws dynamodb wait table-not-exists \
  --region "$AWS_REGION" \
  --table-name "$TABLE_NAME"
```

Verify each target independently. Expected results are empty inventories or service-specific not-found responses:

```bash
aws apigateway get-rest-api --region "$AWS_REGION" --rest-api-id "$API_ID"
aws lambda list-functions --region "$AWS_REGION" --query "Functions[?FunctionName=='$CREATE_FUNCTION_NAME' || FunctionName=='$REDIRECT_FUNCTION_NAME'].FunctionName" --output json
aws dynamodb list-tables --region "$AWS_REGION" --query "TableNames[?@=='$TABLE_NAME']" --output json
aws iam get-role --role-name "$ROLE_NAME"
aws iam list-policies --scope Local --query "Policies[?PolicyName=='${ROLE_NAME}-dynamodb-policy']" --output json
aws logs describe-log-groups --region "$AWS_REGION" --log-group-name-prefix "/aws/lambda/$CREATE_FUNCTION_NAME" --output json
aws logs describe-log-groups --region "$AWS_REGION" --log-group-name-prefix "/aws/lambda/$REDIRECT_FUNCTION_NAME" --output json
```

## What this lab teaches

1. A serverless application is a chain of relationships, not a list of resources.
2. IAM trust, IAM permissions, Lambda invoke permissions, and API Gateway integrations solve different problems.
3. `AWS_PROXY` reduces mapping boilerplate but makes the Lambda event and response contract important.
4. API Gateway deployments are snapshots; a configured method is not automatically live.
5. A positive test and a negative test validate different application paths.
6. The strongest operational evidence comes from reading state back after each dependency is created.
7. Cleanup is part of the acceptance criteria because serverless resources and log groups can remain after the happy-path test.

## Source and scope

Adapted from the [CloudProjects Simple URL Shortener recipe](https://github.com/mzazon/cloud-projects/tree/main/aws/simple-url-shortener-gateway-dynamodb). This repository contains a sanitized engineering write-up and reference handlers, not a copy of the catalog instructions or private execution data.
