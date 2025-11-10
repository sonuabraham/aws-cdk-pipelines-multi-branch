# GitHub Token Setup Guide

This guide explains how to set up and manage GitHub personal access tokens for the CDK multi-branch pipeline.

## Overview

The pipeline uses GitHub personal access tokens for:
- Fetching repository information (default branch) during deployment
- Making GitHub API calls with higher rate limits (5000/hour vs 60/hour unauthenticated)

## Prerequisites

- AWS CLI configured with appropriate credentials
- Access to AWS Secrets Manager in your deployment region
- GitHub account with access to the target repository

## Creating a GitHub Personal Access Token

1. Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
   - URL: https://github.com/settings/tokens

2. Click "Generate new token" → "Generate new token (classic)"

3. Configure the token:
   - **Note**: Enter a descriptive name (e.g., "CDK Pipeline - MyRepo")
   - **Expiration**: Choose an appropriate expiration period
   - **Scopes**: Select the following:
     - `repo` (Full control of private repositories) - if using private repos
     - `public_repo` (Access public repositories) - if using public repos only

4. Click "Generate token"

5. **Important**: Copy the token immediately - you won't be able to see it again!

## Storing the Token in AWS Secrets Manager

### Option 1: Using the Helper Script (Recommended)

#### Linux/macOS:
```bash
./scripts/setup-github-token.sh --token ghp_your_token_here
```

#### Windows:
```cmd
scripts\setup-github-token.bat --token ghp_your_token_here
```

#### Custom Configuration:
```bash
# Use custom secret name and region
./scripts/setup-github-token.sh \
  --token ghp_your_token_here \
  --secret-name my-custom-secret-name \
  --region us-east-1
```

### Option 2: Using AWS CLI Directly

#### Create New Secret:
```bash
aws secretsmanager create-secret \
  --name github-personal-access-token \
  --description "GitHub personal access token for API calls" \
  --secret-string "ghp_your_token_here" \
  --region ap-southeast-2
```

#### Update Existing Secret:
```bash
aws secretsmanager put-secret-value \
  --secret-id github-personal-access-token \
  --secret-string "ghp_your_token_here" \
  --region ap-southeast-2
```

### Option 3: Using AWS Console

1. Open AWS Secrets Manager console
2. Click "Store a new secret"
3. Select "Other type of secret"
4. Choose "Plaintext" tab
5. Paste your GitHub token
6. Click "Next"
7. Enter secret name: `github-personal-access-token`
8. Add description: "GitHub personal access token for API calls"
9. Click "Next" → "Next" → "Store"

## Configuring the Pipeline

Update your `config.ini` file:

```ini
[general]
github_owner=your-github-username
github_repo=your-repo-name
github_connection_arn=arn:aws:codestar-connections:region:account:connection/connection-id
region=ap-southeast-2

[credentials]
# Optional: GitHub personal access token for API calls (stored in AWS Secrets Manager)
github_token_secret_name=github-personal-access-token
```

## IAM Permissions

The pipeline automatically grants the following Lambda functions access to the GitHub token secret:
- `LambdaTriggerCreateBranch` - For branch creation events
- `LambdaTriggerDestroyBranch` - For branch deletion events

Required IAM permissions:
```json
{
  "Effect": "Allow",
  "Action": [
    "secretsmanager:GetSecretValue"
  ],
  "Resource": "arn:aws:secretsmanager:region:account:secret:github-personal-access-token-*"
}
```

## Security Best Practices

### Token Security
- ✅ **DO**: Store tokens in AWS Secrets Manager
- ✅ **DO**: Use the minimum required scopes
- ✅ **DO**: Set token expiration dates
- ✅ **DO**: Rotate tokens regularly (every 90 days recommended)
- ❌ **DON'T**: Commit tokens to version control
- ❌ **DON'T**: Share tokens via email or chat
- ❌ **DON'T**: Log token values in application logs

### Secret Management
- Use AWS Secrets Manager automatic rotation when possible
- Enable CloudTrail logging for secret access auditing
- Use IAM policies to restrict secret access to specific roles
- Set appropriate secret retention policies

### Token Scopes
Only grant the minimum required scopes:
- **Public repositories**: `public_repo` scope only
- **Private repositories**: `repo` scope
- **Avoid**: Admin or delete scopes unless absolutely necessary

## Troubleshooting

### Token Not Found
**Error**: `Failed to retrieve GitHub token from Secrets Manager`

**Solutions**:
1. Verify the secret exists:
   ```bash
   aws secretsmanager describe-secret \
     --secret-id github-personal-access-token \
     --region ap-southeast-2
   ```

2. Check the secret name in `config.ini` matches the actual secret name

3. Verify IAM permissions allow `secretsmanager:GetSecretValue`

### Authentication Failed
**Error**: `GitHub authentication failed (HTTP 401)`

**Solutions**:
1. Verify the token is valid:
   ```bash
   curl -H "Authorization: token YOUR_TOKEN" \
     https://api.github.com/user
   ```

2. Check if the token has expired

3. Verify the token has the required scopes

4. Regenerate the token if necessary

### Rate Limit Exceeded
**Error**: `GitHub API rate limit exceeded (HTTP 403)`

**Solutions**:
1. Ensure you're using an authenticated token (increases limit from 60 to 5000/hour)

2. Check current rate limit status:
   ```bash
   curl -H "Authorization: token YOUR_TOKEN" \
     https://api.github.com/rate_limit
   ```

3. Wait for the rate limit to reset (shown in response headers)

4. Consider using a GitHub App instead of personal access token for higher limits

### Repository Not Found
**Error**: `GitHub repository not found (HTTP 404)`

**Solutions**:
1. Verify the repository name in `config.ini` is correct

2. Check the token has access to the repository:
   ```bash
   curl -H "Authorization: token YOUR_TOKEN" \
     https://api.github.com/repos/owner/repo
   ```

3. For private repos, ensure the token has `repo` scope

4. Verify the repository owner/organization name is correct

## Token Rotation

### Manual Rotation
1. Generate a new GitHub token (see "Creating a GitHub Personal Access Token")
2. Update the secret in AWS Secrets Manager:
   ```bash
   ./scripts/setup-github-token.sh --token ghp_new_token_here
   ```
3. No pipeline redeployment needed - changes take effect immediately

### Automated Rotation
AWS Secrets Manager supports automatic rotation for certain secret types. For GitHub tokens:
1. Create a Lambda function to generate new tokens via GitHub API
2. Configure Secrets Manager rotation
3. Update GitHub token programmatically

**Note**: GitHub API doesn't support programmatic token generation for personal access tokens. Consider using GitHub Apps for automated rotation.

## Monitoring

### CloudWatch Logs
Monitor Lambda function logs for token-related issues:
```bash
aws logs tail /aws/lambda/LambdaTriggerCreateBranch --follow
```

### CloudTrail
Audit secret access:
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=github-personal-access-token \
  --max-results 10
```

### Metrics
Track GitHub API usage:
- Monitor rate limit headers in API responses
- Set up CloudWatch alarms for authentication failures
- Track secret access patterns

## Additional Resources

- [GitHub Personal Access Tokens Documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [GitHub API Rate Limiting](https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting)
- [AWS CodeStar Connections](https://docs.aws.amazon.com/dtconsole/latest/userguide/welcome-connections.html)
