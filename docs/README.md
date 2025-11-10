# Documentation Overview

Welcome to the CDK Multi-Branch Pipeline documentation. This guide will help you navigate the available documentation based on your needs.

## Choose Your Path

### 🚀 New to This Project?

Start here if you're setting up the pipeline for the first time with a new GitHub repository:

1. **[Quick Start Guide](quick-start-github.md)** - Get up and running in 30 minutes
2. Follow the main [README.md](../README.md) for detailed setup instructions

### 🔄 Migrating from CodeCommit?

If you have an existing pipeline using AWS CodeCommit and want to migrate to GitHub:

1. **[CodeCommit to GitHub Migration Guide](github-migration-guide.md)** - Complete migration walkthrough

### 🔧 Setting Up Specific Features

#### GitHub Personal Access Token

For improved GitHub API access and private repository support:

- **[GitHub Token Setup Guide](github-token-setup.md)**

**When you need this:**
- Using private GitHub repositories
- Experiencing GitHub API rate limiting
- Want higher API rate limits (5000/hour vs 60/hour)

#### GitHub Webhooks

For automatic branch pipeline creation and deletion:

- **[GitHub Webhook Setup Guide](github-webhook-setup.md)**

**When you need this:**
- Want automatic pipeline creation when branches are created
- Want automatic pipeline cleanup when branches are deleted
- Prefer hands-off branch management

## Documentation Structure

```
docs/
├── README.md                      # This file - documentation overview
├── quick-start-github.md          # 30-minute setup guide for new users
├── github-token-setup.md          # GitHub personal access token configuration
├── github-webhook-setup.md        # Webhook setup for automatic branch management
└── github-migration-guide.md      # CodeCommit to GitHub migration guide
```

## Common Scenarios

### Scenario 1: First-Time Setup with Public GitHub Repository

**Minimum Required Steps:**
1. Create GitHub repository
2. Push code to GitHub
3. Create CodeStar Connection
4. Update config.ini
5. Deploy pipeline

**Recommended Guides:**
- [Quick Start Guide](quick-start-github.md)
- Main [README.md](../README.md)

**Optional Enhancements:**
- [GitHub Token Setup](github-token-setup.md) - For better rate limits
- [GitHub Webhook Setup](github-webhook-setup.md) - For automatic branch management

### Scenario 2: First-Time Setup with Private GitHub Repository

**Required Steps:**
1. Create private GitHub repository
2. Push code to GitHub
3. Create CodeStar Connection
4. **Set up GitHub personal access token** (required for private repos)
5. Update config.ini
6. Deploy pipeline

**Required Guides:**
- [Quick Start Guide](quick-start-github.md)
- [GitHub Token Setup](github-token-setup.md) - **Required for private repos**

**Optional Enhancements:**
- [GitHub Webhook Setup](github-webhook-setup.md) - For automatic branch management

### Scenario 3: Migrating from CodeCommit

**Required Steps:**
1. Create GitHub repository
2. Migrate repository content
3. Create CodeStar Connection
4. Set up GitHub personal access token
5. Update config.ini
6. Destroy old pipelines
7. Deploy new pipelines

**Required Guide:**
- [CodeCommit to GitHub Migration Guide](github-migration-guide.md) - Complete walkthrough

### Scenario 4: Adding Webhooks to Existing Setup

**Required Steps:**
1. Ensure pipeline is deployed with GitHub configuration
2. Run webhook setup script
3. Configure webhook in GitHub

**Required Guide:**
- [GitHub Webhook Setup](github-webhook-setup.md)

## Helper Scripts

The project includes helper scripts to simplify common tasks:

### GitHub Token Setup

```bash
# Linux/macOS
./scripts/setup-github-token.sh --token ghp_your_token_here

# Windows
scripts\setup-github-token.bat --token ghp_your_token_here
```

**What it does:**
- Stores your GitHub personal access token in AWS Secrets Manager
- Configures proper secret name and format
- Validates the token is stored correctly

### GitHub Webhook Setup

```bash
# Linux/macOS
./scripts/setup-github-webhook.sh

# Windows
scripts\setup-github-webhook.bat
```

**What it does:**
- Retrieves webhook URL from CloudFormation outputs
- Retrieves webhook secret from Secrets Manager
- Provides instructions for GitHub webhook configuration

## Troubleshooting

If you encounter issues, check the [Troubleshooting section](../README.md#troubleshooting) in the main README.

Common issues and solutions:

| Issue | Solution |
|-------|----------|
| CodeStar Connection not authorized | Complete authorization in AWS Console |
| GitHub API rate limit exceeded | Set up GitHub personal access token |
| Repository not found | Verify config.ini settings |
| Webhook not triggering | Check webhook configuration in GitHub |
| Pipeline fails to deploy | Review CloudFormation events |

## Additional Resources

### AWS Documentation

- [AWS CDK Pipelines](https://docs.aws.amazon.com/cdk/api/latest/docs/pipelines-readme.html)
- [AWS CodeStar Connections](https://docs.aws.amazon.com/dtconsole/latest/userguide/welcome-connections.html)
- [AWS CodePipeline](https://docs.aws.amazon.com/codepipeline/)

### GitHub Documentation

- [GitHub Personal Access Tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
- [GitHub Webhooks](https://docs.github.com/en/developers/webhooks-and-events/webhooks)
- [GitHub API](https://docs.github.com/en/rest)

## Getting Help

1. **Check Documentation**: Review the relevant guide for your scenario
2. **Check Troubleshooting**: See [README.md#troubleshooting](../README.md#troubleshooting)
3. **Check CloudWatch Logs**: Most errors are logged in CloudWatch
4. **Check CloudFormation Events**: Stack deployment errors are detailed here
5. **GitHub Issues**: Report bugs or request features in the repository

## Contributing

Found an issue with the documentation or have suggestions for improvement?

1. Open an issue in the repository
2. Submit a pull request with improvements
3. Share your feedback and use cases

## Quick Reference

### Configuration File (config.ini)

```ini
[general]
# GitHub configuration
github_owner=your-github-username
github_repo=your-repository-name
github_connection_arn=arn:aws:codestar-connections:region:account:connection/connection-id
region=ap-southeast-2

[credentials]
# Optional: GitHub personal access token
github_token_secret_name=github-personal-access-token
```

### Deployment Command

```bash
./initial-deploy.sh \
  --dev_account_id YOUR_DEV_ACCOUNT_ID \
  --dev_profile_name YOUR_DEV_PROFILE \
  --prod_account_id YOUR_PROD_ACCOUNT_ID \
  --prod_profile_name YOUR_PROD_PROFILE
```

### Useful AWS CLI Commands

```bash
# Check CodeStar Connection status
aws codestar-connections get-connection --connection-arn YOUR_ARN

# List pipelines
aws codepipeline list-pipelines

# Check pipeline status
aws codepipeline get-pipeline-state --name PIPELINE_NAME

# View CloudFormation events
aws cloudformation describe-stack-events --stack-name STACK_NAME

# Check secret in Secrets Manager
aws secretsmanager describe-secret --secret-id SECRET_NAME
```

## Document Versions

- **Quick Start Guide**: For new users, streamlined setup
- **Main README**: Comprehensive setup with all options
- **Token Setup Guide**: Detailed GitHub token configuration
- **Webhook Setup Guide**: Detailed webhook configuration
- **Migration Guide**: CodeCommit to GitHub migration

Choose the guide that best matches your needs and experience level.
