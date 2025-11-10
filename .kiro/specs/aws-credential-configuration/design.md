# Design Document

## Overview

This design addresses the AWS credential configuration issue in the CDK multi-branch pipeline application. The current implementation fails during synthesis because it attempts to create a boto3 CodeCommit client without proper credential handling. The solution implements a robust credential management strategy with graceful error handling and multiple authentication method support.

The design focuses on three key improvements:
1. Graceful error handling with clear user guidance
2. Support for multiple AWS credential methods (SSO, access keys, profiles, IAM roles)
3. Optional bypass mechanism for local development and testing

## Architecture

### Current Flow
```
app.py starts
  ↓
Read config.ini
  ↓
Create boto3 codecommit client (FAILS HERE if credentials missing)
  ↓
Call get_repository()
  ↓
Extract default_branch
  ↓
Create CDK stack
  ↓
Synthesize
```

### Proposed Flow
```
app.py starts
  ↓
Read config.ini
  ↓
Check SKIP_CODECOMMIT_VALIDATION env var
  ↓
  ├─ If True: Use fallback default_branch value
  │   └─ Log warning message
  │
  └─ If False: Attempt CodeCommit API call
      ↓
      Try: Create boto3 client & get_repository()
      ↓
      Catch: Handle credential errors gracefully
      │   ↓
      │   Display helpful error message
      │   Suggest credential configuration options
      │   Exit with clear status
      ↓
Extract default_branch (from API or fallback)
  ↓
Create CDK stack
  ↓
Synthesize
```

## Components and Interfaces

### 1. Credential Validation Module

**Purpose**: Encapsulate AWS credential handling logic

**Location**: New file `cdk_pipelines_multi_branch/utils/aws_credentials.py`

**Interface**:
```python
def get_default_branch(
    repository_name: str,
    region: str,
    skip_validation: bool = False,
    fallback_branch: str = "master"
) -> str:
    """
    Retrieve the default branch from CodeCommit repository.
    
    Args:
        repository_name: Name of the CodeCommit repository
        region: AWS region where repository exists
        skip_validation: If True, skip API call and return fallback
        fallback_branch: Branch name to use when skipping validation
        
    Returns:
        Default branch name
        
    Raises:
        CredentialConfigurationError: When credentials are missing/invalid
    """
```

**Error Classes**:
```python
class CredentialConfigurationError(Exception):
    """Raised when AWS credentials are not properly configured"""
    
    def __init__(self, original_error: Exception):
        self.original_error = original_error
        self.message = self._build_helpful_message()
        super().__init__(self.message)
    
    def _build_helpful_message(self) -> str:
        """Build user-friendly error message with configuration guidance"""
```

### 2. Configuration Enhancement

**Purpose**: Add skip validation option to config.ini

**Changes to config.ini**:
```ini
[general]
repository_name=cdk-pipelines-multi-branch
codebuild_project_name_prefix=CodeBuild
region=ap-southeast-2

[credentials]
# Set to true to skip CodeCommit API validation during synthesis
# Useful for local development without AWS credentials
skip_codecommit_validation=false
# Default branch to use when skipping validation
fallback_default_branch=master
```

### 3. Application Entry Point Updates

**Purpose**: Integrate credential handling into app.py

**Changes to app.py**:
- Import the new credential validation module
- Read skip_validation configuration
- Replace direct boto3 client creation with function call
- Handle CredentialConfigurationError exceptions
- Log appropriate messages based on validation mode

## Data Models

### Configuration Structure
```python
@dataclass
class CredentialConfig:
    """Configuration for AWS credential handling"""
    skip_validation: bool
    fallback_branch: str
    repository_name: str
    region: str
```

### Error Response Structure
```python
@dataclass
class CredentialErrorGuidance:
    """Structured guidance for credential configuration"""
    error_type: str  # "sso_missing", "no_credentials", "invalid_profile"
    primary_message: str
    configuration_steps: List[str]
    documentation_links: List[str]
```

## Error Handling

### Error Categories and Responses

#### 1. Missing SSO Configuration
**Detection**: `InvalidConfigError` with message containing "sso_start_url" or "sso_region"

**Response**:
```
ERROR: AWS SSO configuration is incomplete

Your AWS profile is configured for SSO but missing required settings.

To fix this, add the following to your AWS config file (~/.aws/config):

[profile default]
sso_start_url = https://your-sso-portal.awsapps.com/start
sso_region = us-east-1
sso_account_id = 123456789012
sso_role_name = YourRoleName
region = ap-southeast-2

Alternatively, you can:
1. Use AWS access keys by setting AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
2. Skip CodeCommit validation for local testing by setting SKIP_CODECOMMIT_VALIDATION=true

Documentation: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html
```

#### 2. No Credentials Found
**Detection**: `NoCredentialsError`

**Response**:
```
ERROR: No AWS credentials found

The application cannot find AWS credentials to authenticate with AWS services.

Choose one of the following options:

1. Configure AWS SSO:
   aws configure sso

2. Set environment variables:
   export AWS_ACCESS_KEY_ID=your_access_key
   export AWS_SECRET_ACCESS_KEY=your_secret_key
   export AWS_DEFAULT_REGION=ap-southeast-2

3. Skip CodeCommit validation (for local testing):
   export SKIP_CODECOMMIT_VALIDATION=true

Documentation: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html
```

#### 3. Invalid Profile
**Detection**: `ProfileNotFound`

**Response**:
```
ERROR: AWS profile not found

The specified AWS profile does not exist in your configuration.

To fix this:
1. List available profiles: aws configure list-profiles
2. Set the correct profile: export AWS_PROFILE=your_profile_name
3. Or create a new profile: aws configure --profile your_profile_name

For local testing without credentials:
export SKIP_CODECOMMIT_VALIDATION=true
```

### Error Handling Flow

```python
try:
    # Attempt to create client and call API
    client = boto3.client('codecommit', region_name=region)
    response = client.get_repository(repositoryName=repository_name)
    return response['repositoryMetadata']['defaultBranch']
    
except InvalidConfigError as e:
    if 'sso_start_url' in str(e) or 'sso_region' in str(e):
        raise CredentialConfigurationError(e, error_type='sso_missing')
    raise CredentialConfigurationError(e, error_type='invalid_config')
    
except NoCredentialsError as e:
    raise CredentialConfigurationError(e, error_type='no_credentials')
    
except ProfileNotFound as e:
    raise CredentialConfigurationError(e, error_type='invalid_profile')
    
except ClientError as e:
    # Handle AWS service errors (permissions, repository not found, etc.)
    raise CredentialConfigurationError(e, error_type='aws_service_error')
```

## Testing Strategy

### Unit Tests

**File**: `tests/unit/test_aws_credentials.py`

**Test Cases**:
1. `test_get_default_branch_success` - Verify successful API call returns correct branch
2. `test_get_default_branch_with_skip_validation` - Verify fallback branch is used when skipping
3. `test_credential_error_sso_missing` - Verify SSO error produces correct guidance
4. `test_credential_error_no_credentials` - Verify no credentials error produces correct guidance
5. `test_credential_error_invalid_profile` - Verify profile error produces correct guidance
6. `test_fallback_branch_configuration` - Verify custom fallback branch is respected

**Mocking Strategy**:
- Mock `boto3.client()` to simulate various credential scenarios
- Mock `get_repository()` responses
- Use `pytest.raises()` to verify exception handling

### Integration Tests

**File**: `tests/integration/test_app_synthesis.py`

**Test Cases**:
1. `test_synthesis_with_valid_credentials` - Full synthesis with mocked AWS credentials
2. `test_synthesis_with_skip_validation` - Synthesis using skip validation mode
3. `test_synthesis_fails_gracefully_without_credentials` - Verify error message quality

**Environment Setup**:
- Use temporary config.ini files
- Set/unset environment variables for different scenarios
- Capture stdout/stderr to verify error messages

### Manual Testing Scenarios

1. **SSO Configuration Missing**
   - Configure AWS profile for SSO without sso_start_url
   - Run `cdk synth`
   - Verify helpful error message appears

2. **Skip Validation Mode**
   - Set `SKIP_CODECOMMIT_VALIDATION=true`
   - Run `cdk synth`
   - Verify synthesis succeeds with warning message

3. **Valid Credentials**
   - Configure proper AWS credentials
   - Run `cdk synth`
   - Verify synthesis succeeds without warnings

4. **CI/CD Environment**
   - Use IAM role credentials (simulated)
   - Run `cdk synth`
   - Verify synthesis succeeds

## Implementation Considerations

### Backward Compatibility
- Existing deployments with valid credentials will continue to work unchanged
- No breaking changes to the CDK stack or pipeline configuration
- Config.ini changes are additive (new optional section)

### Environment Variable Priority
The skip validation can be controlled via:
1. Environment variable `SKIP_CODECOMMIT_VALIDATION` (highest priority)
2. Config.ini setting `skip_codecommit_validation`
3. Default behavior: false (perform validation)

### Logging Strategy
- Use Python's `logging` module for consistent output
- Log levels:
  - `WARNING`: When skipping CodeCommit validation
  - `ERROR`: When credential configuration fails
  - `INFO`: Successful CodeCommit API calls (optional, for debugging)

### Security Considerations
- Never log or display actual credential values
- Error messages should not expose sensitive account information
- Follow AWS best practices for credential management
- Recommend temporary credentials over long-term access keys

### Performance Impact
- Minimal: Only adds try-catch overhead and conditional logic
- No additional API calls
- Skip validation mode actually improves performance by avoiding API call

## Alternative Approaches Considered

### 1. Remove CodeCommit API Call Entirely
**Pros**: Simplifies code, no credential issues
**Cons**: Loses dynamic default branch detection, requires manual configuration
**Decision**: Rejected - dynamic branch detection is valuable for the multi-branch workflow

### 2. Lazy Loading of Default Branch
**Pros**: Defer credential requirement until actually needed
**Cons**: Complicates stack initialization, may fail later in synthesis
**Decision**: Rejected - fail-fast approach is clearer for users

### 3. Credential Validation Pre-Check
**Pros**: Validate credentials before attempting any AWS calls
**Cons**: Adds complexity, may not catch all credential issues
**Decision**: Rejected - let boto3 handle validation naturally, catch exceptions

## Dependencies

### New Dependencies
None - uses existing boto3 and botocore exception classes

### Updated Dependencies
None - no version changes required

## Migration Path

### For Existing Users
1. Pull latest code changes
2. Optionally add `[credentials]` section to config.ini for skip validation feature
3. Continue using existing AWS credential configuration
4. No action required if credentials are already properly configured

### For New Users
1. Clone repository
2. Configure AWS credentials using any supported method
3. Optionally use skip validation mode for initial testing
4. Run initial-deploy.sh as documented

## Documentation Updates Required

### README.md
- Add "Troubleshooting" section with credential configuration guidance
- Document the skip validation option for local development
- Add examples of different credential configuration methods

### New Documentation
- Create `docs/credential-configuration.md` with detailed setup instructions
- Include examples for SSO, access keys, and IAM roles
- Add troubleshooting flowchart
