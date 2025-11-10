# Design Document

## Overview

This design migrates the CDK multi-branch pipeline from AWS CodeCommit to GitHub as the source repository. The migration involves three main areas:

1. **Pipeline Source Configuration**: Replace CodeCommit source with GitHub source using CodeStar Connections
2. **Branch Detection**: Replace CodeCommit API calls with GitHub API calls for default branch detection
3. **Event Handling**: Replace CodeCommit event triggers with GitHub webhooks or EventBridge for branch creation/deletion

The design maintains backward compatibility where possible and provides clear migration paths for existing deployments.

## Architecture

### Current Architecture (CodeCommit)
```
┌─────────────┐
│ CodeCommit  │
│ Repository  │
└──────┬──────┘
       │
       ├─── Branch Events ───> EventBridge ───> Lambda (Create/Delete Branch)
       │
       └─── Pipeline Source ──> CodePipeline ──> CDK Synth & Deploy
```

### Proposed Architecture (GitHub)
```
┌─────────────┐
│   GitHub    │
│ Repository  │
└──────┬──────┘
       │
       ├─── Webhooks ───> API Gateway ───> Lambda ───> EventBridge ───> Lambda (Create/Delete Branch)
       │                                                                  
       └─── Pipeline Source ──> CodeStar Connection ──> CodePipeline ──> CDK Synth & Deploy
                                                                          
┌──────────────┐
│  GitHub API  │ <─── initial-deploy.sh (Get Default Branch)
└──────────────┘
```

## Components and Interfaces

### 1. Pipeline Source Configuration

**Current Implementation**:
```python
from aws_cdk.aws_codecommit import Repository
from aws_cdk.pipelines import CodePipelineSource

repo = Repository.from_repository_name(self, 'ImportedRepo', repo_name)

source = CodePipelineSource.code_commit(
    repository=repo,
    trigger=aws_codepipeline_actions.CodeCommitTrigger.POLL,
    branch=branch
)
```

**New Implementation**:
```python
from aws_cdk.pipelines import CodePipelineSource

source = CodePipelineSource.connection(
    repo_string=f"{github_owner}/{github_repo}",
    branch=branch,
    connection_arn=github_connection_arn,
    trigger_on_push=True
)
```

**Configuration Changes**:
```ini
[general]
repository_name=cdk-pipelines-multi-branch  # Keep for backward compatibility
github_owner=your-github-username
github_repo=cdk-pipelines-multi-branch
github_connection_arn=arn:aws:codestar-connections:region:account:connection/connection-id
region=ap-southeast-2

[credentials]
github_token_secret_name=github-personal-access-token  # For API calls
```

### 2. Branch Detection Module

**Location**: Update `initial-deploy.sh` or create new Python module

**Current Implementation** (CodeCommit):
```bash
export BRANCH=$(aws codecommit get-repository \
    --repository-name ${repository_name} \
    --region ${region} \
    --output json | jq -r '.repositoryMetadata.defaultBranch')
```

**New Implementation** (GitHub):
```bash
# Using GitHub API
export BRANCH=$(curl -s \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO} \
    | jq -r '.default_branch')
```

**Alternative Python Implementation**:
```python
import requests
import os

def get_github_default_branch(owner: str, repo: str, token: str = None) -> str:
    """
    Retrieve default branch from GitHub repository.
    
    Args:
        owner: GitHub repository owner
        repo: GitHub repository name
        token: GitHub personal access token (optional for public repos)
        
    Returns:
        Default branch name
        
    Raises:
        GitHubAPIError: When API call fails
    """
    url = f"https://api.github.com/repos/{owner}/{repo}"
    headers = {"Accept": "application/vnd.github.v3+json"}
    
    if token:
        headers["Authorization"] = f"token {token}"
    
    response = requests.get(url, headers=headers)
    response.raise_for_status()
    
    return response.json()["default_branch"]
```

### 3. Event Handling for Branch Operations

**Challenge**: GitHub doesn't natively integrate with EventBridge like CodeCommit does.

**Solution Options**:

#### Option A: GitHub Webhooks + API Gateway + Lambda
```
GitHub Webhook → API Gateway → Lambda (Webhook Handler) → EventBridge → Lambda (Branch Handler)
```

**Webhook Handler Lambda**:
- Validates GitHub webhook signature
- Parses webhook payload
- Publishes custom event to EventBridge
- Returns 200 OK to GitHub

#### Option B: GitHub App + Polling
```
CloudWatch Event (Scheduled) → Lambda (Poll GitHub) → EventBridge → Lambda (Branch Handler)
```

**Polling Lambda**:
- Periodically checks GitHub for branch changes
- Compares with DynamoDB state table
- Publishes events for new/deleted branches

#### Option C: Manual Trigger Only
```
Remove automatic branch creation/deletion
Require manual pipeline creation for feature branches
```

**Recommendation**: Option A (Webhooks) for real-time response, with Option C as fallback for simplicity.

### 4. CodeStar Connection Setup

**Prerequisites**:
1. Create CodeStar Connection in AWS Console
2. Authorize connection with GitHub
3. Note the connection ARN

**CDK Code** (if creating connection via CDK):
```python
# Note: CodeStar Connections must be manually authorized in console
# This creates the connection resource, but manual authorization is required

from aws_cdk.aws_codestarconnections import CfnConnection

github_connection = CfnConnection(
    self,
    "GitHubConnection",
    connection_name="github-connection",
    provider_type="GitHub"
)

# Output the ARN for manual authorization
CfnOutput(
    self,
    "GitHubConnectionArn",
    value=github_connection.attr_connection_arn,
    description="GitHub connection ARN - requires manual authorization in console"
)
```

## Data Models

### Configuration Structure

```python
@dataclass
class RepositoryConfig:
    """Configuration for source repository"""
    # GitHub configuration
    github_owner: str
    github_repo: str
    github_connection_arn: str
    github_token_secret_name: Optional[str] = None
    
    # Legacy CodeCommit (for backward compatibility)
    codecommit_repo_name: Optional[str] = None
    
    # Common
    region: str
    default_branch: str = "main"
```

### Webhook Payload Structure

```python
@dataclass
class GitHubBranchEvent:
    """Parsed GitHub webhook event"""
    event_type: str  # "create" or "delete"
    ref: str  # "refs/heads/branch-name"
    ref_type: str  # "branch"
    repository: str  # "owner/repo"
    sender: str  # GitHub username
    timestamp: str
```

## Error Handling

### GitHub API Errors

**Rate Limiting**:
```python
if response.status_code == 403 and 'rate limit' in response.text.lower():
    raise GitHubRateLimitError(
        "GitHub API rate limit exceeded. "
        "Provide a personal access token to increase limits."
    )
```

**Authentication Errors**:
```python
if response.status_code == 401:
    raise GitHubAuthError(
        "GitHub authentication failed. "
        "Check your personal access token or connection configuration."
    )
```

**Repository Not Found**:
```python
if response.status_code == 404:
    raise GitHubRepositoryNotFoundError(
        f"GitHub repository {owner}/{repo} not found. "
        "Check repository name and access permissions."
    )
```

### CodeStar Connection Errors

**Connection Not Authorized**:
- Error during pipeline execution if connection not authorized
- Provide clear instructions to authorize in AWS Console
- Include connection ARN in error message

### Webhook Validation Errors

**Invalid Signature**:
```python
def validate_github_signature(payload: bytes, signature: str, secret: str) -> bool:
    """Validate GitHub webhook signature"""
    import hmac
    import hashlib
    
    expected = 'sha256=' + hmac.new(
        secret.encode(),
        payload,
        hashlib.sha256
    ).hexdigest()
    
    return hmac.compare_digest(expected, signature)
```

## Testing Strategy

### Unit Tests

**Test Cases**:
1. `test_github_source_configuration` - Verify GitHub source is correctly configured
2. `test_github_api_default_branch` - Mock GitHub API and verify branch detection
3. `test_github_api_rate_limit_handling` - Verify rate limit error handling
4. `test_webhook_signature_validation` - Verify webhook signature validation
5. `test_webhook_payload_parsing` - Verify webhook payload is correctly parsed

### Integration Tests

**Test Cases**:
1. `test_pipeline_with_github_source` - Deploy pipeline with GitHub source
2. `test_branch_detection_from_github` - Verify default branch detection works
3. `test_webhook_end_to_end` - Send test webhook and verify Lambda execution

### Manual Testing

1. **CodeStar Connection Setup**:
   - Create connection in AWS Console
   - Authorize with GitHub
   - Verify connection status is "Available"

2. **Pipeline Deployment**:
   - Run initial-deploy.sh with GitHub configuration
   - Verify pipeline is created
   - Verify pipeline can pull code from GitHub

3. **Webhook Testing**:
   - Create a test branch in GitHub
   - Verify webhook is received
   - Verify branch creation Lambda is triggered

## Implementation Considerations

### Migration Path

**For Existing CodeCommit Users**:
1. Keep CodeCommit support as fallback
2. Add GitHub configuration as optional
3. Auto-detect which source to use based on configuration
4. Provide migration guide in documentation

**Detection Logic**:
```python
if config.get('github_owner') and config.get('github_repo'):
    # Use GitHub
    source = CodePipelineSource.connection(...)
elif config.get('codecommit_repo_name'):
    # Use CodeCommit
    source = CodePipelineSource.code_commit(...)
else:
    raise ValueError("No repository configuration found")
```

### Security Considerations

1. **GitHub Token Storage**:
   - Store in AWS Secrets Manager
   - Use IAM roles for Lambda access
   - Rotate tokens regularly

2. **Webhook Secret**:
   - Generate strong random secret
   - Store in Secrets Manager
   - Use for signature validation

3. **Connection Permissions**:
   - Limit CodeStar Connection to specific repository
   - Use least privilege IAM policies
   - Audit connection usage

### Performance Impact

- **GitHub API**: Rate limits apply (5000/hour authenticated, 60/hour unauthenticated)
- **Webhooks**: Near real-time, minimal latency
- **CodeStar Connection**: No additional latency vs CodeCommit

### Backward Compatibility

- Keep CodeCommit code paths intact
- Add GitHub as alternative, not replacement
- Allow configuration-based selection
- Document migration process

## Alternative Approaches Considered

### 1. GitHub Actions Instead of CodePipeline
**Pros**: Native GitHub integration, simpler setup
**Cons**: Loses AWS-native features, requires rewrite of entire pipeline
**Decision**: Rejected - too disruptive

### 2. AWS CodePipeline GitHub V1 Source
**Pros**: Simpler than CodeStar Connections
**Cons**: Deprecated, uses OAuth tokens, less secure
**Decision**: Rejected - CodeStar Connections is the modern approach

### 3. Mirror GitHub to CodeCommit
**Pros**: Minimal code changes
**Cons**: Adds complexity, sync delays, duplicate storage
**Decision**: Rejected - unnecessary complexity

## Dependencies

### New Dependencies
- `requests` - For GitHub API calls (if using Python implementation)
- AWS CodeStar Connections service

### Updated Configuration
- config.ini - Add GitHub-specific settings
- Secrets Manager - Store GitHub tokens

## Documentation Updates Required

### README.md
- Add GitHub setup instructions
- Document CodeStar Connection creation
- Provide GitHub token generation guide
- Update deployment commands

### New Documentation
- `docs/github-migration.md` - Step-by-step migration guide
- `docs/github-webhooks.md` - Webhook setup instructions
- `docs/troubleshooting-github.md` - Common GitHub integration issues

