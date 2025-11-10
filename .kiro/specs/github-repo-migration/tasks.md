# Implementation Plan

- [x] 1. Update configuration file structure for GitHub





  - Add GitHub-specific configuration fields to config.ini (github_owner, github_repo, github_connection_arn)
  - Add optional github_token_secret_name field for API authentication
  - Keep existing CodeCommit fields for backward compatibility
  - _Requirements: 4.1, 4.2, 4.3_

- [x] 2. Modify CDK stack to support GitHub source





  - Update imports to include CodePipelineSource.connection
  - Add logic to detect whether to use GitHub or CodeCommit based on configuration
  - Replace CodeCommit repository reference with GitHub connection for GitHub mode
  - Update pipeline source from CodePipelineSource.code_commit to CodePipelineSource.connection when using GitHub
  - Remove CodeCommit-specific IAM policy statements when using GitHub
  - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 3. Update initial-deploy.sh for GitHub branch detection




  - Add logic to check if GitHub configuration is present
  - Implement GitHub API call to retrieve default branch using curl
  - Add GitHub token retrieval from AWS Secrets Manager if configured
  - Implement fallback to CodeCommit API if GitHub is not configured
  - Add error handling for GitHub API rate limiting and authentication failures
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [x] 4. Create GitHub webhook handler infrastructure (Optional - for branch events)





  - Create API Gateway REST API for webhook endpoint
  - Create Lambda function to receive and validate GitHub webhooks
  - Implement webhook signature validation using HMAC SHA256
  - Parse GitHub webhook payload for branch create/delete events
  - Publish custom events to EventBridge for branch operations
  - Store webhook secret in AWS Secrets Manager
  - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [x] 5. Update branch creation/deletion Lambda functions for GitHub




  - Modify Lambda environment variables to support GitHub repository format
  - Update any CodeCommit-specific API calls to work with GitHub repository references
  - Ensure Lambda functions can handle both CodeCommit and GitHub event formats
  - _Requirements: 3.1, 3.2_

- [x] 6. Add GitHub token management





  - Create AWS Secrets Manager secret for GitHub personal access token
  - Update deployment script to retrieve token from Secrets Manager
  - Add IAM permissions for Lambda functions to access GitHub token secret
  - Implement secure token handling (no logging of token values)
  - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [x] 7. Update documentation






  - Add GitHub setup instructions to README.md
  - Document CodeStar Connection creation and authorization process
  - Create migration guide for existing CodeCommit users
  - Document GitHub webhook setup (if implementing webhook handler)
  - Add troubleshooting section for common GitHub integration issues
  - _Requirements: 1.1, 2.1, 3.1, 4.1, 5.1_

- [x] 8. Create helper script for CodeStar Connection setup





  - Write script to create CodeStar Connection via AWS CLI
  - Add instructions for manual authorization in AWS Console
  - Output connection ARN for use in configuration
  - _Requirements: 1.2, 5.1_

