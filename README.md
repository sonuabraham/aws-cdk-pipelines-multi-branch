# Using AWS CDK Pipelines and AWS Lambda for multi-branch pipeline management and infrastructure deployment. 

 This project shows how to use the [AWS CDK Pipelines module](https://docs.aws.amazon.com/cdk/api/latest/docs/pipelines-readme.html) to follow a Gitflow development model Software development teams often follow a strict branching strategy during the
development lifecycle of a solution. It is common for newly created branches to need their own isolated
copy of infrastructure resources in order to develop new features.

[CDK Pipelines](https://docs.aws.amazon.com/cdk/api/latest/docs/pipelines-readme.html) is a construct library module for painless continuous delivery of AWS CDK applications.
CDK Pipelines are self-updating: if you add application stages or stacks, the pipeline automatically
reconfigures itself to deploy those new stages and/or stacks.

The following solution creates a new AWS CDK Pipeline within a development account for every new
branch created in the source repository (GitHub or AWS CodeCommit). When a branch is deleted, the pipeline and
all related resources are destroyed from the account as well. This GitFlow model for infrastructure
provisioning allows developers to work independently from each other, concurrently, even in the same
stack of the application.


## Overview of the solution

![Architecture diagram](./diagrams/architecture.png)

## Prerequisites 
Before setting up this project, you should have the following prerequisites:
* An [AWS account](https://signin.aws.amazon.com/signin?redirect_uri=https%3A%2F%2Fportal.aws.amazon.com%2Fbilling%2Fsignup%2Fresume&client_id=signup)
* [AWS CDK](https://docs.aws.amazon.com/cdk/latest/guide/getting_started.html#getting_started_install) installed
* Python3 installed
* Git installed
* A GitHub account

## Initial setup 

### Option 1: Using GitHub (Recommended)

This guide walks you through setting up the multi-branch pipeline with a new GitHub repository.

**Quick Start**: For a streamlined setup process, see the [Quick Start Guide](docs/quick-start-github.md) (30 minutes).

#### Step 1: Create a New GitHub Repository

1. Go to [GitHub](https://github.com/new) and create a new repository
2. Enter a repository name (e.g., `cdk-pipelines-multi-branch`)
3. Choose visibility:
   - **Public**: Free, accessible to everyone
   - **Private**: Requires GitHub subscription, restricted access
4. **Do not** initialize with README, .gitignore, or license (we'll push existing code)
5. Click **Create repository**
6. Copy the repository URL (e.g., `https://github.com/your-username/cdk-pipelines-multi-branch.git`)

#### Step 2: Push Code to GitHub

Clone or download this project code, then push it to your new GitHub repository:

```bash
# If you haven't already, clone or download this project
# cd into the project directory

# Initialize git (if not already initialized)
git init

# Add all files
git add .

# Create initial commit
git commit -m "Initial commit: CDK multi-branch pipeline"

# Add your GitHub repository as remote
git remote add origin https://github.com/your-username/your-repo.git

# Push to GitHub (use 'main' or 'master' depending on your default branch)
git branch -M main
git push -u origin main
```

**Note**: If you already have this code in a git repository, simply add your new GitHub repository as a remote and push.

#### Step 3: Create a CodeStar Connection

AWS CodeStar Connections enables secure authentication between AWS and GitHub.

1. Open the [AWS Developer Tools Console](https://console.aws.amazon.com/codesuite/settings/connections)
2. Click **Create connection**
3. Select **GitHub** as the provider
4. Enter a connection name (e.g., `github-connection`)
5. Click **Connect to GitHub**
6. Authorize AWS Connector for GitHub in the popup window
7. Select the GitHub account/organization and click **Install**
8. Back in the AWS Console, click **Connect**
9. Copy the **Connection ARN** (format: `arn:aws:codestar-connections:region:account:connection/connection-id`)

**Note**: The connection must be in the "Available" status before proceeding.

For detailed instructions, see the [AWS CodeStar Connections documentation](https://docs.aws.amazon.com/dtconsole/latest/userguide/connections-create-github.html).

#### Step 4: Configure GitHub Personal Access Token (Optional but Recommended)

The pipeline uses GitHub API to detect the default branch. While this works without authentication for public repositories, using a personal access token provides:
- Higher rate limits (5000/hour vs 60/hour)
- Access to private repositories
- More reliable branch detection

**Create and store the token:**

1. Generate a GitHub personal access token:
   - Go to [GitHub Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens)
   - Click **Generate new token (classic)**
   - Select scopes: `repo` (for private repos) or `public_repo` (for public repos only)
   - Copy the generated token

2. Store the token in AWS Secrets Manager using the helper script:
   ```bash
   # Linux/macOS
   ./scripts/setup-github-token.sh --token ghp_your_token_here
   
   # Windows
   scripts\setup-github-token.bat --token ghp_your_token_here
   ```

For detailed token setup instructions, see [docs/github-token-setup.md](docs/github-token-setup.md).

#### Step 5: Update Configuration File

Update the `config.ini` file with your GitHub repository details:

```ini
[general]
# GitHub configuration
github_owner=your-github-username
github_repo=your-repository-name
github_connection_arn=arn:aws:codestar-connections:region:account:connection/connection-id
region=ap-southeast-2

# Optional: Keep for backward compatibility with CodeCommit
repository_name=cdk-pipelines-multi-branch

[credentials]
# Optional: GitHub personal access token (stored in AWS Secrets Manager)
github_token_secret_name=github-personal-access-token
```

**Configuration Notes:**
- `github_owner`: Your GitHub username or organization name
- `github_repo`: The repository name (not the full URL)
- `github_connection_arn`: The ARN from Step 1
- `github_token_secret_name`: The name of the secret in AWS Secrets Manager (optional)



### Option 2: Using AWS CodeCommit (Alternative)

If you prefer to use AWS CodeCommit instead of GitHub:

1. [Create a new AWS CodeCommit repository](https://docs.aws.amazon.com/codecommit/latest/userguide/how-to-create-repository.html) in your AWS Account
2. Push your code to the CodeCommit repository
3. Update `config.ini` with your CodeCommit repository name and region:
   ```ini
   [general]
   repository_name=your-codecommit-repo
   region=ap-southeast-2
   ```

**Note**: If you're migrating from an existing CodeCommit setup to GitHub, see the [Migration Guide](docs/github-migration-guide.md).

### Deploy the Pipeline

Make sure to set up a fresh python environment. Install the dependencies:

`pip install -r requirements.txt`

Run the initial-deploy.sh script to bootstrap the development and production environments and to
deploy the default pipeline. You’ll be asked to provide the following parameters: (1) Development
account ID, (2) Development account AWS profile name (3) Production account ID, (4) Production
account AWS profile name.

`sh ./initial-deploy.sh --dev_account_id <YOUR DEV ACCOUNT ID> --
dev_profile_name <YOUR DEV PROFILE NAME> --prod_account_id <YOUR PRODUCTION
ACCOUNT ID> --prod_profile_name <YOUR PRODUCTION PROFILE NAME>`

### GitHub Webhook Setup (Optional)

If using GitHub, you can optionally set up webhooks for automatic branch pipeline creation/deletion. This enables the pipeline to automatically respond to branch creation and deletion events in your GitHub repository.

**Benefits of webhook setup:**
- Automatic pipeline creation when new branches are created
- Automatic pipeline cleanup when branches are deleted
- Near real-time response to repository events
- No manual intervention required

**Setup steps:**

1. Deploy the main pipeline (it includes webhook infrastructure when using GitHub)
2. Run the webhook setup helper script:
   - **Linux/Mac**: `./scripts/setup-github-webhook.sh`
   - **Windows**: `scripts\setup-github-webhook.bat`
3. Follow the instructions to configure the webhook in your GitHub repository

For detailed webhook setup instructions, see [docs/github-webhook-setup.md](docs/github-webhook-setup.md).

**Note**: Webhook setup is optional. Without webhooks, you can still manually trigger pipeline creation for new branches.

## How to use

[Lambda S3 trigger project](https://github.com/aws-samples/aws-cdk-examples/tree/master/python/lambda-s3-trigger) from AWS CDK Samples is used as infrastructure resources to demonstrate
this solution. The content is placed inside the *src* directory and is deployed by the pipeline. Replace the content of this repository with your infrastructure code. Use [CDK Constructs](https://docs.aws.amazon.com/cdk/latest/guide/constructs.html) to combine your infrastructure code into one stack and reference this in the application stage inside *src/application_stage.py*. 

### Create a feature branch 

On your machine’s local copy of the repository, create a new feature branch using the git commands
below. Replace user-feature-123 with a unique name for your feature branch. Note: this feature branch name must comply with the [AWS CodePipeline naming restrictions](https://docs.aws.amazon.com/codepipeline/latest/userguide/limits.html#:~:text=Pipeline%20names%20cannot%20exceed%20100,letters%20A%20through%20Z%2C%20inclusive.) for it will be used to name a unique
pipeline later in this walkthrough. 

```
# Create the feature branch
git checkout -b user-feature-123
git push origin user-feature-123
```

The first AWS Lambda function will deploy the CodeBuild project which then deployes the feature
pipeline. This can take a few minutes. You can log into the AWS Console and see the CodeBuild project
running under AWS CodeBuild. After the build is successfully finished, you can see the deployed feature pipeline under AWS
CodePipelines.

### Destroy a feature branch 
There are two common ways for removing feature branches. The first one is related to a pull request,
also known as a “PR”, which occurs when merging a feature branch back into the default branch. Once it
is merged, the feature branch will be automatically closed. The second way is to delete the feature
branch explicitly by running the below git commands.

```
# delete branch local
git branch -d user-feature-123

# delete branch remote
git push origin --delete user-feature-123
```


## Documentation

This project includes comprehensive documentation to help you set up and use the multi-branch pipeline.

**📚 [Documentation Overview](docs/README.md)** - Start here to find the right guide for your needs

### Quick Links

- **[Quick Start Guide](docs/quick-start-github.md)** - 30-minute setup for new GitHub repositories
- **[GitHub Token Setup](docs/github-token-setup.md)** - Configure GitHub personal access tokens
- **[GitHub Webhook Setup](docs/github-webhook-setup.md)** - Enable automatic branch management
- **[CodeCommit Migration Guide](docs/github-migration-guide.md)** - Migrate from existing CodeCommit setup

### Helper Scripts

The `scripts/` directory contains helper scripts to simplify setup:

- `setup-github-token.sh` / `setup-github-token.bat` - Store GitHub tokens in AWS Secrets Manager
- `setup-github-webhook.sh` / `setup-github-webhook.bat` - Configure GitHub webhooks

### Architecture

- **[Architecture Diagram](diagrams/architecture.png)** - Visual overview of the solution architecture

## Troubleshooting

### GitHub Integration Issues

#### CodeStar Connection Not Authorized

**Symptom**: Pipeline fails with "Connection is not in AVAILABLE state" or "Connection ARN is invalid"

**Solution**:
1. Open the [AWS Developer Tools Console](https://console.aws.amazon.com/codesuite/settings/connections)
2. Find your connection and check its status
3. If status is "Pending", click **Update pending connection**
4. Complete the GitHub authorization flow:
   - Click **Install a new app** or **Use existing app**
   - Select your GitHub account/organization
   - Authorize AWS Connector for GitHub
   - Grant access to the repository
5. Verify the status changes to "Available"
6. Copy the correct Connection ARN and update `config.ini`

**Common causes**:
- Connection was created but never authorized
- GitHub App installation was revoked
- Connection ARN in config.ini is incorrect or from wrong region
- Insufficient permissions in GitHub organization

**Verification**:
```bash
# Check connection status
aws codestar-connections get-connection \
  --connection-arn YOUR_CONNECTION_ARN \
  --query 'Connection.ConnectionStatus' \
  --output text
```

Expected output: `AVAILABLE`

#### GitHub API Rate Limit Exceeded

**Symptom**: `initial-deploy.sh` fails with "API rate limit exceeded"

**Solution**:
1. Set up a GitHub personal access token (see [docs/github-token-setup.md](docs/github-token-setup.md))
2. This increases the rate limit from 60/hour to 5000/hour
3. Verify the token is stored in Secrets Manager and referenced in `config.ini`

#### Repository Not Found

**Symptom**: Pipeline fails with "Repository not found" or 404 error

**Solution**:
1. Verify `github_owner` and `github_repo` in `config.ini` are correct
2. For private repositories, ensure the CodeStar Connection has access
3. Check that the GitHub personal access token has the `repo` scope
4. Test access manually:
   ```bash
   curl -H "Authorization: token YOUR_TOKEN" \
     https://api.github.com/repos/owner/repo
   ```

#### Webhook Not Triggering Pipelines

**Symptom**: Creating/deleting branches in GitHub doesn't trigger pipeline actions

**Solution**:
1. Verify the webhook is configured in GitHub (Settings → Webhooks)
2. Check webhook delivery history for errors
3. Review CloudWatch logs for the webhook handler Lambda
4. Ensure the webhook secret matches between GitHub and Secrets Manager
5. See [docs/github-webhook-setup.md](docs/github-webhook-setup.md) for detailed troubleshooting

#### Default Branch Detection Fails

**Symptom**: `initial-deploy.sh` cannot determine the default branch

**Solution**:
1. Manually specify the branch:
   ```bash
   export BRANCH=main
   ./initial-deploy.sh --dev_account_id ... --dev_profile_name ...
   ```
2. Verify GitHub API access:
   ```bash
   curl https://api.github.com/repos/owner/repo
   ```
3. Check CloudWatch logs for API errors

### General Pipeline Issues

#### Pipeline Fails to Deploy

**Symptom**: CDK deployment fails or pipeline execution fails

**Solution**:
1. Check CloudFormation stack events for error details
2. Verify IAM permissions for the pipeline role
3. Ensure all required AWS services are available in your region
4. Review CodeBuild logs for build failures

#### Branch Pipeline Not Created

**Symptom**: New branch doesn't trigger pipeline creation

**Solution**:
1. Check EventBridge rules are enabled
2. Review Lambda function logs (`LambdaTriggerCreateBranch`)
3. Verify the branch name complies with [AWS CodePipeline naming restrictions](https://docs.aws.amazon.com/codepipeline/latest/userguide/limits.html)
4. Ensure CodeBuild project creation succeeded

#### Branch Pipeline Not Destroyed

**Symptom**: Deleted branch doesn't trigger pipeline cleanup

**Solution**:
1. Review Lambda function logs (`LambdaTriggerDestroyBranch`)
2. Manually delete the CloudFormation stack if needed:
   ```bash
   aws cloudformation delete-stack --stack-name cdk-pipelines-multi-branch-branch-name
   ```
3. Check for resources preventing stack deletion (S3 buckets, etc.)

### Configuration Issues

#### Invalid Configuration Format

**Symptom**: Deployment fails with configuration parsing errors

**Solution**:
1. Verify `config.ini` syntax is correct
2. Ensure all required fields are present
3. Check for typos in ARNs and names
4. Validate the configuration:
   ```python
   import configparser
   config = configparser.ConfigParser()
   config.read('config.ini')
   print(config['general'])
   ```

#### Missing AWS Credentials

**Symptom**: AWS CLI commands fail with authentication errors

**Solution**:
1. Configure AWS CLI profiles:
   ```bash
   aws configure --profile dev-profile
   ```
2. Verify credentials are valid:
   ```bash
   aws sts get-caller-identity --profile dev-profile
   ```
3. Ensure the profile has necessary permissions

### Getting Help

If you continue to experience issues:

1. **Check CloudWatch Logs**: Most errors are logged in CloudWatch
2. **Review CloudFormation Events**: Stack deployment errors are detailed here
3. **Enable Debug Logging**: Set environment variables for verbose output
4. **Consult Documentation**: See the `docs/` directory for detailed guides
5. **GitHub Issues**: Report bugs or request features in the repository

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.

