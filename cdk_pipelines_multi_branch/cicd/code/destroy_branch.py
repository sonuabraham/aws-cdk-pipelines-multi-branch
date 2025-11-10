import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

client = boto3.client('codebuild')
region = os.environ['AWS_REGION']
role_arn = os.environ['CODE_BUILD_ROLE_ARN']
account_id = os.environ['ACCOUNT_ID']
artifact_bucket_name = os.environ['ARTIFACT_BUCKET']
codebuild_name_prefix = os.environ['CODEBUILD_NAME_PREFIX']
dev_stage_name = os.environ['DEV_STAGE_NAME']


def generate_build_spec(branch):
    return f"""version: 0.2
env:
  variables:
    BRANCH: {branch}
    DEV_ACCOUNT_ID: {account_id}
    PROD_ACCOUNT_ID: {account_id}
    REGION: {region}
phases:
  pre_build:
    commands:
      - npm install -g aws-cdk && pip install -r requirements.txt
  build:
    commands:
      - cdk destroy cdk-pipelines-multi-branch-{branch} --force
      - aws cloudformation delete-stack --stack-name {dev_stage_name}-{branch}
      - aws s3 rm s3://{artifact_bucket_name}/{branch} --recursive"""


def handler(event, context):
    """
    Lambda function handler for branch deletion events.
    Supports both CodeCommit and GitHub event formats.
    """
    logger.info(f"Received event: {event}")
    
    try:
        detail = event.get('detail', {})
        reference_type = detail.get('referenceType')

        if reference_type == 'branch':
            branch = detail.get('referenceName')
            repo_name = detail.get('repositoryName')
            
            if not branch:
                logger.error(f"Missing required field: branch={branch}")
                return
            
            # Detect if this is a GitHub event (repository name contains '/')
            is_github = '/' in repo_name if repo_name else False
            
            logger.info(f"Processing branch deletion: branch={branch}, repo={repo_name}, is_github={is_github}")
            
            destroy_project_name = f'{codebuild_name_prefix}-{branch}-destroy'
            create_project_name = f'{codebuild_name_prefix}-{branch}-create'
            
            logger.info(f"Creating CodeBuild destroy project: {destroy_project_name}")
            
            client.create_project(
                name=destroy_project_name,
                description="Build project to destroy branch resources",
                source={
                    'type': 'S3',
                    'location': f'{artifact_bucket_name}/{branch}/{create_project_name}/',
                    'buildspec': generate_build_spec(branch)
                },
                artifacts={
                    'type': 'NO_ARTIFACTS'
                },
                environment={
                    'type': 'LINUX_CONTAINER',
                    'image': 'aws/codebuild/standard:6.0',
                    'computeType': 'BUILD_GENERAL1_SMALL'
                },
                serviceRole=role_arn
            )

            logger.info(f"Starting CodeBuild destroy project: {destroy_project_name}")
            
            client.start_build(
                projectName=destroy_project_name
            )

            logger.info(f"Deleting CodeBuild projects: {destroy_project_name}, {create_project_name}")
            
            client.delete_project(
                name=destroy_project_name
            )

            client.delete_project(
                name=create_project_name
            )
            
            logger.info(f"Successfully processed branch deletion for: {branch}")
            
    except Exception as e:
        logger.error(f"Error processing branch deletion: {e}", exc_info=True)
        raise
