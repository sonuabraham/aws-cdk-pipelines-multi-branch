# Quick Start Guide: GitHub Setup

This guide provides a streamlined setup process for getting the CDK multi-branch pipeline running with GitHub in under 30 minutes.

## Prerequisites Checklist

Before you begin, ensure you have:

- ✅ AWS account with admin access
- ✅ [AWS CLI](https://aws.amazon.com/cli/) installed and configured
- ✅ [AWS CDK](https://docs.aws.amazon.com/cdk/latest/guide/getting_started.html) installed
- ✅ Python 3.7 or later installed
- ✅ Git installed
- ✅ GitHub account

## Setup Steps (30 minutes)

### 1. Create GitHub Repository (5 minutes)

1. Go to https://github.com/new
2. Repository name: `cdk-pipelines-multi-branch` (or your preferred name)
3. Choose **Public** or **Private**
4. **Do not** initialize with README
5. Click **Create repository**
6. Keep this tab open - you'll need the repository URL

### 2. Push Code to GitHub (5 minutes)

```bash
# Navigate to your project directory
cd /path/to/cdk-pipelines-multi-branch

# Initialize git if needed
git init

# Add all files
git add .

# Initial commit
git commit -m "Initial commit: CDK multi-branch pipeline"

# Add GitHub remote (replace with your repository URL)
git remote add origin https://github.com/YOUR-USERNAME/YOUR-REPO.git

# Push to GitHub
git branch -M main
git push -u origin main
```

### 3. Create AWS CodeStar Connection (5 minutes)

1. Open [AWS Developer Tools Console](https://console.aws.amazon.com/codesuite/settings/connections)
2. Click **Create connection**
3. Provider: **GitHub**
4. Connection name: `github-connection`
5. Click **Connect to GitHub**
6. In the popup:
   - Click **Authorize AWS Connector for GitHub**
   - Select your GitHub account
   - Click **Install**
7. Back in AWS Console, click **Connect**
8. **Copy the Connection ARN** - you'll need this next

Example ARN: `arn:aws:codestar-connections:ap-southeast-2:123456789012:connection/abc123...`

### 4. Create GitHub Personal Access Token (5 minutes)

1. Go to https://github.com/settings/tokens
2. Click **Generate new token** → **Generate new token (classic)**
3. Token name: `CDK Pipeline - [Your Repo Name]`
4. Expiration: **90 days** (or your preference)
5. Select scopes:
   - ✅ **repo** (for private repos) OR
   - ✅ **public_repo** (for public repos only)
6. Click **Generate token**
7. **Copy the token immediately** (starts with `ghp_`)

### 5. Store Token in AWS Secrets Manager (2 minutes)

```bash
# Linux/macOS
./scripts/setup-github-token.sh --token ghp_YOUR_TOKEN_HERE

# Windows
scripts\setup-github-token.bat --token ghp_YOUR_TOKEN_HERE
```

### 6. Update Configuration (3 minutes)

Edit `config.ini`:

```ini
[general]
# GitHub configuration
github_owner=YOUR-GITHUB-USERNAME
github_repo=YOUR-REPO-NAME
github_connection_arn=arn:aws:codestar-connections:REGION:ACCOUNT:connection/CONNECTION-ID
region=ap-southeast-2

[credentials]
# GitHub token secret name
github_token_secret_name=github-personal-access-token
```

**Replace**:
- `YOUR-GITHUB-USERNAME` - Your GitHub username or organization
- `YOUR-REPO-NAME` - Your repository name (not the full URL)
- `CONNECTION-ID` - The connection ARN from step 3
- `REGION` - Your AWS region (e.g., `ap-southeast-2`)
- `ACCOUNT` - Your AWS account ID

### 7. Install Dependencies (2 minutes)

```bash
# Create virtual environment (recommended)
python -m venv .venv

# Activate virtual environment
# Linux/macOS:
source .venv/bin/activate
# Windows:
.venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### 8. Deploy the Pipeline (5-10 minutes)

```bash
./initial-deploy.sh \
  --dev_account_id YOUR_DEV_ACCOUNT_ID \
  --dev_profile_name YOUR_DEV_PROFILE \
  --prod_account_id YOUR_PROD_ACCOUNT_ID \
  --prod_profile_name YOUR_PROD_PROFILE
```

**Note**: If you're using the same account for dev and prod, use the same account ID and profile for both.

The script will:
1. Detect your default branch from GitHub
2. Bootstrap CDK in dev and prod accounts
3. Deploy the main pipeline

### 9. Verify Deployment (2 minutes)

Check the pipeline in AWS Console:

```bash
# Open CodePipeline console
aws codepipeline list-pipelines

# Check pipeline status
aws codepipeline get-pipeline-state --name cdk-pipelines-multi-branch-main
```

Or visit: https://console.aws.amazon.com/codesuite/codepipeline/pipelines

### 10. Set Up Webhooks (Optional, 3 minutes)

For automatic branch pipeline creation:

```bash
# Linux/macOS
./scripts/setup-github-webhook.sh

# Windows
scripts\setup-github-webhook.bat
```

Follow the script instructions to configure the webhook in GitHub.

## Verification

### Test Branch Pipeline Creation

1. Create a test branch:
   ```bash
   git checkout -b test-feature
   git push origin test-feature
   ```

2. Wait 2-3 minutes

3. Check for new pipeline:
   ```bash
   aws codepipeline list-pipelines | grep test-feature
   ```

4. Clean up:
   ```bash
   git push origin --delete test-feature
   ```

## Common Issues

### "Connection is not in AVAILABLE state"

**Fix**: Complete the GitHub authorization in AWS Console:
1. Go to [Connections](https://console.aws.amazon.com/codesuite/settings/connections)
2. Click **Update pending connection**
3. Complete authorization

### "API rate limit exceeded"

**Fix**: Ensure your GitHub token is properly configured in Secrets Manager (Step 5)

### "Repository not found"

**Fix**: Verify `github_owner` and `github_repo` in `config.ini` match your GitHub repository exactly

### Pipeline fails to deploy

**Fix**: Check CloudFormation events:
```bash
aws cloudformation describe-stack-events \
  --stack-name cdk-pipelines-multi-branch-main \
  --max-items 10
```

## Next Steps

1. **Customize Infrastructure**: Edit files in `src/` directory
2. **Create Feature Branches**: Test the multi-branch functionality
3. **Set Up Webhooks**: Enable automatic pipeline creation (Step 10)
4. **Review Documentation**: See [docs/](../docs/) for detailed guides

## Getting Help

- **Detailed Setup**: See main [README.md](../README.md)
- **Token Setup**: [docs/github-token-setup.md](github-token-setup.md)
- **Webhook Setup**: [docs/github-webhook-setup.md](github-webhook-setup.md)
- **Troubleshooting**: [README.md#troubleshooting](../README.md#troubleshooting)

## Estimated Costs

Running this pipeline incurs AWS costs:

- **CodePipeline**: ~$1/month per pipeline
- **CodeBuild**: ~$0.005/minute (free tier: 100 minutes/month)
- **S3**: Minimal storage costs
- **Lambda**: Free tier covers most usage
- **Secrets Manager**: ~$0.40/month per secret

**Estimated monthly cost**: $5-20 depending on usage

## Clean Up

To remove all resources:

```bash
# Destroy main pipeline
cdk destroy cdk-pipelines-multi-branch-main

# Delete branch pipelines
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?starts_with(StackName, 'cdk-pipelines-multi-branch-')].StackName" \
  --output text | xargs -n1 aws cloudformation delete-stack --stack-name

# Delete GitHub token secret (optional)
aws secretsmanager delete-secret \
  --secret-id github-personal-access-token \
  --force-delete-without-recovery
```
