#!/usr/bin/env python3
import configparser
import os

import aws_cdk as cdk
import boto3
import cdk_nag

from cdk_pipelines_multi_branch.cicd.cdk_pipelines_multi_branch_stack import CdkPipelinesMultiBranchStack

app = cdk.App()

# retrieve configuration variables
global_config = configparser.ConfigParser()
global_config.read('config.ini')
region = global_config.get('general', 'region')
codebuild_prefix = global_config.get('general', 'codebuild_project_name_prefix')
current_branch = os.getenv("BRANCH","master")
#current_branch = "master"
#print(current_branch)

# Check if GitHub configuration is present
github_owner = global_config.get('general', 'github_owner', fallback=None)
github_repo = global_config.get('general', 'github_repo', fallback=None)
github_connection_arn = global_config.get('general', 'github_connection_arn', fallback=None)

# Detect whether to use GitHub or CodeCommit
use_github = github_owner and github_repo and github_connection_arn

if use_github:
    # GitHub mode - default branch will be retrieved by initial-deploy.sh
    # For now, use environment variable or fallback to 'main'
    default_branch = os.getenv("DEFAULT_BRANCH", "main")
    print(f"Using GitHub repository: {github_owner}/{github_repo}")
    print(f"Default branch: {default_branch}")
else:
    # CodeCommit mode - retrieve default branch from CodeCommit API
    repository_name = global_config.get('general', 'repository_name')
    codecommit_client = boto3.client('codecommit', region_name=region)
    repository = codecommit_client.get_repository(
        repositoryName=repository_name
    )
    print(repository)
    default_branch = repository['repositoryMetadata']['defaultBranch']

config = {
    'dev_account_id': os.environ['DEV_ACCOUNT_ID'],
    'branch': current_branch,
    'default_branch': default_branch,
    'region': region,
    'codebuild_prefix': codebuild_prefix,
}

# Add repository-specific configuration
if use_github:
    config['github_owner'] = github_owner
    config['github_repo'] = github_repo
    config['github_connection_arn'] = github_connection_arn
    # Optional: GitHub token secret name
    github_token_secret = global_config.get('credentials', 'github_token_secret_name', fallback=None)
    if github_token_secret:
        config['github_token_secret_name'] = github_token_secret
else:
    config['repository_name'] = global_config.get('general', 'repository_name')

# Only the default branch resources will be deployed to the production environment.
if current_branch == default_branch:
    config['prod_account_id'] = os.environ['PROD_ACCOUNT_ID']

CdkPipelinesMultiBranchStack(
    app,
    f"cdk-pipelines-multi-branch-{current_branch}",
    config,
    env=cdk.Environment(account=config['dev_account_id'], region=region)
)

cdk.Aspects.of(app).add(cdk_nag.AwsSolutionsChecks())

app.synth()
