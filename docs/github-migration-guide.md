# Migration Guide: CodeCommit to GitHub

This guide provides step-by-step instructions for migrating your existing CDK multi-branch pipeline from AWS CodeCommit to GitHub.

## Overview

Migrating from CodeCommit to GitHub involves:
1. Migrating your repository content from CodeCommit to GitHub
2. Setting up GitHub authentication with AWS
3. Updating pipeline configuration
4. Redeploying the pipeline infrastructure
5. Verifying the migration

**Estimated Time**: 30-60 minutes

**Downtime**: Minimal (pipelines will be recreated)

## Prerequisites

- Existing CDK multi-branch pipeline using CodeCommit
- GitHub account with repository creation permissions
- AWS CLI configured with appropriate credentials
- Git installed locally
- Admin access to AWS account

## Migration Steps

### Step 1: Backup Current Configuration

Before making changes, backup your current setup:

```bash
# Backup configuration
cp config.ini config.ini.backup

# Export current stack information
aws cloudformation describe-stacks \
  --stack-name cdk-pipelines-multi-branch-main \
  --output json > stack-backup.json

# List all branch pipelines
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?starts_with(StackName, 'cdk-pipelines-multi-branch-')].StackName" \
  --output table
```

### Step 2: Create GitHub Repository

1. **Create a new repository on GitHub**:
   - Go to https://github.com/new
   - Enter repository name (e.g., `cdk-pipelines-multi-branch`)
   - Choose visibility (Public or Private)
   - **Do not** initialize with README, .gitignore, or license
   - Click **Create repository**

2. **Note the repository details**:
   - Repository owner (username or organization)
   - Repository name

### Step 3: Migrate Repository Content

#### Option A: Mirror the Entire Repository (Recommended)

This preserves all branches, tags, and commit history:

```bash
# Clone the CodeCommit repository as a mirror
git clone --mirror codecommit://your-codecommit-repo local-mirror
cd local-mirror

# Add GitHub as a remote
git remote add github https://github.com/your-username/your-repo.git

# Push all branches and tags to GitHub
git push --mirror github

# Clean up
cd ..
rm -rf local-mirror
```

#### Option B: Migrate Specific Branches

If you only want to migrate certain branches:

```bash
# Clone the CodeCommit repository
git clone codecommit://your-codecommit-repo
cd your-codecommit-repo

# Add GitHub as a remote
git remote add github https://github.com/your-username/your-repo.git

# Push main branch
git push github main

# Push other branches as needed
git push github develop
git push github feature-branch-1

# Update default remote
git remote set-url origin https://github.com/your-username/your-repo.git
```

### Step 4: Set Up GitHub Authentication

#### Create CodeStar Connection

1. Open the [AWS Developer Tools Console](https://console.aws.amazon.com/codesuite/settings/connections)
2. Click **Create connection**
3. Select **GitHub** as the provider
4. Enter connection name: `github-connection`
5. Click **Connect to GitHub**
6. Authorize AWS Connector for GitHub
7. Select your GitHub account/organization
8. Click **Install** and **Connect**
9. **Copy the Connection ARN** - you'll need this for configuration

#### Set Up GitHub Personal Access Token

1. Generate a token on GitHub:
   - Go to https://github.com/settings/tokens
   - Click **Generate new token (classic)**
   - Name: `CDK Pipeline - [Your Repo]`
   - Expiration: Choose appropriate duration
   - Scopes:
     - ✅ `repo` (for private repos)
     - ✅ `public_repo` (for public repos)
   - Click **Generate token**
   - **Copy the token immediately**

2. Store the token in AWS Secrets Manager:
   ```bash
   # Linux/macOS
   ./scripts/setup-github-token.sh --token ghp_your_token_here
   
   # Windows
   scripts\setup-github-token.bat --token ghp_your_token_here
   ```

### Step 5: Update Configuration

Update your `config.ini` file:

```ini
[general]
# Add GitHub configuration
github_owner=your-github-username
github_repo=your-repository-name
github_connection_arn=arn:aws:codestar-connections:region:account:connection/connection-id

# Keep CodeCommit config for reference (optional)
# repository_name=your-codecommit-repo

region=ap-southeast-2

[credentials]
# Add GitHub token secret name
github_token_secret_name=github-personal-access-token
```

**Important**: The pipeline will automatically detect GitHub configuration and use it instead of CodeCommit.

### Step 6: Destroy Existing Pipelines

Before redeploying with GitHub, clean up existing CodeCommit-based pipelines:

```bash
# Destroy the main pipeline
cdk destroy cdk-pipelines-multi-branch-main

# Destroy branch pipelines (if any)
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?starts_with(StackName, 'cdk-pipelines-multi-branch-')].StackName" \
  --output text | xargs -n1 aws cloudformation delete-stack --stack-name

# Wait for deletions to complete
aws cloudformation wait stack-delete-complete --stack-name cdk-pipelines-multi-branch-main
```

**Note**: This will temporarily take down your pipelines. Plan accordingly.

### Step 7: Deploy with GitHub

Deploy the pipeline with the new GitHub configuration:

```bash
# Ensure you're using the updated config.ini
cat config.ini

# Run the initial deployment script
./initial-deploy.sh \
  --dev_account_id YOUR_DEV_ACCOUNT_ID \
  --dev_profile_name YOUR_DEV_PROFILE \
  --prod_account_id YOUR_PROD_ACCOUNT_ID \
  --prod_profile_name YOUR_PROD_PROFILE
```

The script will:
1. Detect the default branch from GitHub
2. Bootstrap CDK environments
3. Deploy the main pipeline using GitHub as the source

### Step 8: Set Up GitHub Webhooks (Optional)

For automatic branch pipeline creation/deletion:

1. Run the webhook setup script:
   ```bash
   # Linux/macOS
   ./scripts/setup-github-webhook.sh
   
   # Windows
   scripts\setup-github-webhook.bat
   ```

2. Follow the instructions to configure the webhook in GitHub

For detailed webhook setup, see [github-webhook-setup.md](github-webhook-setup.md).

### Step 9: Verify Migration

#### Verify Main Pipeline

1. Check the pipeline in AWS Console:
   ```bash
   aws codepipeline get-pipeline --name cdk-pipelines-multi-branch-main
   ```

2. Verify the source is GitHub:
   - Open [AWS CodePipeline Console](https://console.aws.amazon.com/codesuite/codepipeline/pipelines)
   - Click on `cdk-pipelines-multi-branch-main`
   - Check the Source stage shows GitHub as the provider

3. Trigger a manual execution:
   ```bash
   aws codepipeline start-pipeline-execution --name cdk-pipelines-multi-branch-main
   ```

#### Verify Branch Detection

1. Test default branch detection:
   ```bash
   # Should return your default branch (e.g., "main")
   curl -H "Authorization: token YOUR_GITHUB_TOKEN" \
     https://api.github.com/repos/your-owner/your-repo | jq -r '.default_branch'
   ```

#### Verify Webhook (if configured)

1. Create a test branch in GitHub:
   ```bash
   git checkout -b test-migration-branch
   git push origin test-migration-branch
   ```

2. Check webhook delivery in GitHub:
   - Go to repository **Settings** → **Webhooks**
   - Click on the webhook
   - Check **Recent Deliveries** for successful delivery

3. Verify pipeline creation:
   ```bash
   # Wait a few minutes, then check for the new pipeline
   aws codepipeline list-pipelines | grep test-migration-branch
   ```

4. Clean up test branch:
   ```bash
   git push origin --delete test-migration-branch
   ```

### Step 10: Update Team Documentation

Update your team's documentation to reflect the migration:

1. Update repository URLs in documentation
2. Update CI/CD instructions
3. Inform team members of the new GitHub repository
4. Update any automation scripts that reference CodeCommit

## Post-Migration Tasks

### Clean Up CodeCommit Resources

After verifying the migration is successful, you can optionally clean up CodeCommit resources:

```bash
# List CodeCommit repositories
aws codecommit list-repositories

# Delete the CodeCommit repository (CAREFUL!)
# aws codecommit delete-repository --repository-name your-codecommit-repo
```

**Warning**: Only delete the CodeCommit repository after confirming:
- All branches are migrated to GitHub
- All pipelines are working with GitHub
- Team members have updated their local repositories
- Any external integrations are updated

### Update Local Git Remotes

Team members should update their local repository remotes:

```bash
# Check current remote
git remote -v

# Update origin to GitHub
git remote set-url origin https://github.com/your-username/your-repo.git

# Verify
git remote -v

# Fetch from new remote
git fetch origin
```

### Monitor Initial Runs

Monitor the first few pipeline executions:

1. Check CloudWatch Logs for any errors
2. Verify deployments complete successfully
3. Test application functionality in deployed environments
4. Monitor GitHub webhook deliveries

## Rollback Procedure

If you encounter issues and need to rollback:

### Quick Rollback

1. Restore the backup configuration:
   ```bash
   cp config.ini.backup config.ini
   ```

2. Redeploy with CodeCommit:
   ```bash
   ./initial-deploy.sh \
     --dev_account_id YOUR_DEV_ACCOUNT_ID \
     --dev_profile_name YOUR_DEV_PROFILE \
     --prod_account_id YOUR_PROD_ACCOUNT_ID \
     --prod_profile_name YOUR_PROD_PROFILE
   ```

### Full Rollback

If you need to completely revert:

1. Destroy GitHub-based pipelines
2. Restore configuration from backup
3. Redeploy with CodeCommit configuration
4. Verify CodeCommit pipelines are working
5. Investigate and resolve GitHub migration issues

## Troubleshooting

### Migration Issues

#### CodeStar Connection Not Available

**Problem**: Connection status is "Pending"

**Solution**:
1. Complete the authorization flow in AWS Console
2. Verify GitHub App installation
3. Check connection permissions

#### Repository Content Not Migrated

**Problem**: Branches or commits missing in GitHub

**Solution**:
1. Use `git clone --mirror` to ensure complete migration
2. Verify all branches were pushed: `git branch -r`
3. Check GitHub repository for all expected branches

#### Pipeline Fails After Migration

**Problem**: Pipeline execution fails with GitHub source

**Solution**:
1. Verify CodeStar Connection is "Available"
2. Check GitHub repository permissions
3. Review CloudFormation stack events
4. Check CodeBuild logs for specific errors

#### Webhook Not Working

**Problem**: Branch events don't trigger pipelines

**Solution**:
1. Verify webhook is configured in GitHub
2. Check webhook secret matches Secrets Manager
3. Review API Gateway and Lambda logs
4. See [github-webhook-setup.md](github-webhook-setup.md)

### Performance Issues

#### Slow Pipeline Execution

**Problem**: GitHub-based pipeline is slower than CodeCommit

**Solution**:
- This is expected due to CodeStar Connection overhead
- Typical overhead: 5-10 seconds
- Consider caching strategies in CodeBuild

#### GitHub API Rate Limiting

**Problem**: Frequent API rate limit errors

**Solution**:
1. Ensure GitHub personal access token is configured
2. Verify token is being used (check CloudWatch logs)
3. Consider using GitHub App for higher limits

## Best Practices

### During Migration

1. **Plan for downtime**: Schedule migration during low-activity periods
2. **Test in non-production first**: Migrate a test pipeline before production
3. **Communicate with team**: Inform all stakeholders of the migration timeline
4. **Backup everything**: Keep backups until migration is fully verified
5. **Monitor closely**: Watch logs and metrics during initial runs

### After Migration

1. **Keep CodeCommit temporarily**: Don't delete immediately
2. **Document changes**: Update all relevant documentation
3. **Train team members**: Ensure everyone knows the new workflow
4. **Monitor costs**: GitHub integration may have different cost implications
5. **Review security**: Audit GitHub permissions and access controls

## Cost Considerations

### CodeCommit vs GitHub

| Service | CodeCommit | GitHub |
|---------|-----------|--------|
| Repository hosting | $1/month per active user | Free (public) / $4/month per user (private) |
| API calls | Free | Free (with rate limits) |
| CodeStar Connections | N/A | Free |
| Webhooks | Free (EventBridge) | Free |

**Note**: GitHub may be more cost-effective for teams already using GitHub for other projects.

## Additional Resources

- [GitHub Setup Instructions](../README.md#option-2-using-github-recommended)
- [GitHub Token Setup Guide](github-token-setup.md)
- [GitHub Webhook Setup Guide](github-webhook-setup.md)
- [AWS CodeStar Connections Documentation](https://docs.aws.amazon.com/dtconsole/latest/userguide/welcome-connections.html)
- [GitHub Migration Tools](https://docs.github.com/en/migrations)

## Support

If you encounter issues during migration:

1. Check the [Troubleshooting section](../README.md#troubleshooting) in the main README
2. Review CloudWatch Logs for detailed error messages
3. Consult AWS Support for CodeStar Connection issues
4. Check GitHub Status page for service issues

## Feedback

We'd love to hear about your migration experience! Please share:
- Migration duration
- Issues encountered
- Suggestions for improvement
- Success stories

Open an issue in the repository to provide feedback.
