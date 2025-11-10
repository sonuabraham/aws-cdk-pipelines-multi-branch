# GitHub Webhook Setup Guide

This guide explains how to set up GitHub webhooks to automatically trigger pipeline creation and deletion when branches are created or deleted in your GitHub repository.

## Overview

The GitHub webhook infrastructure consists of:

1. **API Gateway REST API** - Receives webhook events from GitHub
2. **Lambda Function** - Validates webhook signatures and processes events
3. **AWS Secrets Manager** - Stores the webhook secret securely
4. **EventBridge** - Routes branch events to the appropriate Lambda functions
5. **Branch Handler Lambdas** - Create or destroy pipelines based on branch events

## Architecture

```
GitHub Repository
    │
    │ (Webhook)
    ▼
API Gateway (/webhook)
    │
    ▼
Lambda (Webhook Handler)
    │
    ├─ Validate HMAC SHA256 signature
    ├─ Parse branch create/delete events
    │
    ▼
EventBridge (Custom Events)
    │
    ├─ Branch Create Event ──▶ Lambda (Create Branch)
    │
    └─ Branch Delete Event ──▶ Lambda (Destroy Branch)
```

## Prerequisites

1. CDK pipeline stack deployed with GitHub configuration
2. AWS CLI configured with appropriate credentials
3. GitHub repository with admin access

## Setup Steps

### 1. Deploy the Webhook Infrastructure

The webhook infrastructure is automatically deployed when you use GitHub as the source repository. Ensure your `config.ini` has GitHub configuration:

```ini
[general]
github_owner=your-github-username
github_repo=your-repository-name
github_connection_arn=arn:aws:codestar-connections:region:account:connection/connection-id
```

Deploy the stack:

```bash
# Set environment variables
export DEV_ACCOUNT_ID=123456789012
export PROD_ACCOUNT_ID=123456789012
export BRANCH=main

# Deploy
cdk deploy
```

### 2. Retrieve Webhook Configuration

After deployment, you need two pieces of information:

#### Webhook URL

The webhook URL is available in the CloudFormation stack outputs:

```bash
aws cloudformation describe-stacks \
  --stack-name cdk-pipelines-multi-branch-main \
  --query "Stacks[0].Outputs[?OutputKey=='GitHubWebhookURL'].OutputValue" \
  --output text
```

Or use the helper script:

**Linux/Mac:**
```bash
./scripts/setup-github-webhook.sh
```

**Windows:**
```cmd
scripts\setup-github-webhook.bat
```

#### Webhook Secret

The webhook secret is stored in AWS Secrets Manager:

```bash
aws secretsmanager get-secret-value \
  --secret-id github-webhook-secret \
  --query SecretString \
  --output text | jq -r '.secret'
```

### 3. Configure GitHub Webhook

1. Navigate to your GitHub repository
2. Go to **Settings** > **Webhooks** > **Add webhook**
3. Configure the webhook:

   | Field | Value |
   |-------|-------|
   | **Payload URL** | The webhook URL from step 2 |
   | **Content type** | `application/json` |
   | **Secret** | The webhook secret from step 2 |

4. Select **Let me select individual events**:
   - ✅ Branch or tag creation
   - ✅ Branch or tag deletion
   - ✅ Pushes (optional, provides additional branch detection)

5. Ensure **Active** is checked
6. Click **Add webhook**

### 4. Verify Webhook Configuration

After adding the webhook, GitHub will send a ping event. Check:

1. **GitHub Webhook Page**: Should show a green checkmark for the ping event
2. **API Gateway Logs**: Check CloudWatch logs for the webhook handler
3. **Lambda Logs**: Verify the webhook handler processed the ping event

## Webhook Events

The webhook handler processes the following GitHub events:

### Branch Creation

**GitHub Event:** `create` with `ref_type: branch`

**Action:** Triggers the `LambdaTriggerCreateBranch` function to:
- Create a CodeBuild project for the new branch
- Deploy the CDK pipeline stack for the branch

### Branch Deletion

**GitHub Event:** `delete` with `ref_type: branch`

**Action:** Triggers the `LambdaTriggerDestroyBranch` function to:
- Destroy the CDK pipeline stack for the branch
- Clean up CodeBuild projects
- Remove artifacts from S3

### Push Events (Optional)

**GitHub Event:** `push` with `created: true` or `deleted: true`

**Action:** Alternative detection method for branch creation/deletion

## Security

### Webhook Signature Validation

All webhook requests are validated using HMAC SHA256 signatures:

1. GitHub signs each webhook payload with the secret
2. The Lambda function validates the signature before processing
3. Invalid signatures are rejected with a 401 response

### Secret Management

- Webhook secret is generated automatically during deployment
- Stored securely in AWS Secrets Manager
- Lambda function retrieves the secret at runtime
- Secret is cached in Lambda memory for performance

### IAM Permissions

The webhook handler Lambda has minimal permissions:
- Read access to the webhook secret in Secrets Manager
- Permission to publish events to EventBridge
- CloudWatch Logs for monitoring

## Troubleshooting

### Webhook Returns 401 Unauthorized

**Cause:** Signature validation failed

**Solutions:**
1. Verify the secret in GitHub matches the secret in Secrets Manager
2. Check that the secret hasn't been rotated without updating GitHub
3. Ensure the payload is not being modified in transit

### Webhook Returns 500 Internal Server Error

**Cause:** Lambda function error

**Solutions:**
1. Check CloudWatch Logs for the webhook handler Lambda
2. Verify the Lambda has permissions to access Secrets Manager
3. Ensure EventBridge permissions are configured correctly

### Branch Events Not Triggering Pipelines

**Cause:** EventBridge rules not routing events correctly

**Solutions:**
1. Check EventBridge rules are created and enabled
2. Verify the event pattern matches the webhook events
3. Check CloudWatch Logs for the branch handler Lambdas
4. Ensure the branch handler Lambdas have correct permissions

### GitHub Shows Red X for Webhook

**Cause:** Webhook delivery failed

**Solutions:**
1. Verify the webhook URL is correct and accessible
2. Check API Gateway is deployed and healthy
3. Review API Gateway access logs
4. Ensure the Lambda function is not timing out

## Monitoring

### CloudWatch Logs

Monitor the following log groups:

1. `/aws/lambda/GitHubWebhookHandler` - Webhook processing logs
2. `/aws/lambda/LambdaTriggerCreateBranch` - Branch creation logs
3. `/aws/lambda/LambdaTriggerDestroyBranch` - Branch deletion logs
4. `/aws/apigateway/github-webhook-api` - API Gateway access logs

### CloudWatch Metrics

Key metrics to monitor:

- **API Gateway**: Request count, 4XX errors, 5XX errors, latency
- **Lambda**: Invocations, errors, duration, throttles
- **EventBridge**: Invocations, failed invocations

### GitHub Webhook Deliveries

View webhook delivery history in GitHub:
1. Go to repository **Settings** > **Webhooks**
2. Click on the webhook
3. View **Recent Deliveries** tab
4. Click on individual deliveries to see request/response details

## Testing

### Manual Testing

Test the webhook manually using curl:

```bash
# Get the webhook secret
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id github-webhook-secret \
  --query SecretString \
  --output text | jq -r '.secret')

# Create test payload
PAYLOAD='{"ref":"test-branch","ref_type":"branch","repository":{"full_name":"owner/repo"},"sender":{"login":"testuser"}}'

# Generate signature
SIGNATURE=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$SECRET" | sed 's/^.* //')

# Send request
curl -X POST "https://your-api-gateway-url/webhook" \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: create" \
  -H "X-Hub-Signature-256: sha256=$SIGNATURE" \
  -d "$PAYLOAD"
```

### Automated Testing

Create a test branch in GitHub and verify:

1. Webhook is triggered (check GitHub webhook deliveries)
2. Lambda processes the event (check CloudWatch logs)
3. EventBridge routes the event (check EventBridge metrics)
4. Branch handler creates the pipeline (check CodeBuild projects)

## Cleanup

To remove the webhook infrastructure:

1. Delete the webhook from GitHub repository settings
2. Destroy the CDK stack:
   ```bash
   cdk destroy cdk-pipelines-multi-branch-main
   ```
3. Manually delete the webhook secret from Secrets Manager if needed:
   ```bash
   aws secretsmanager delete-secret \
     --secret-id github-webhook-secret \
     --force-delete-without-recovery
   ```

## Cost Considerations

The webhook infrastructure incurs minimal costs:

- **API Gateway**: ~$3.50 per million requests
- **Lambda**: Free tier covers most usage (1M requests/month)
- **Secrets Manager**: ~$0.40 per secret per month
- **EventBridge**: Free for custom events

Estimated monthly cost for typical usage: **< $1**

## Best Practices

1. **Monitor webhook deliveries** regularly in GitHub
2. **Set up CloudWatch alarms** for Lambda errors
3. **Rotate webhook secret** periodically (update both Secrets Manager and GitHub)
4. **Use API Gateway throttling** to prevent abuse
5. **Review CloudWatch Logs** for suspicious activity
6. **Test webhook** after any infrastructure changes

## Additional Resources

- [GitHub Webhooks Documentation](https://docs.github.com/en/developers/webhooks-and-events/webhooks)
- [AWS API Gateway Documentation](https://docs.aws.amazon.com/apigateway/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS EventBridge Documentation](https://docs.aws.amazon.com/eventbridge/)
