@echo off
REM Script to help set up GitHub webhook configuration

echo GitHub Webhook Setup Helper
echo ============================
echo.

REM Check if AWS CLI is installed
where aws >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo Error: AWS CLI is not installed. Please install it first.
    exit /b 1
)

echo Retrieving webhook URL from CloudFormation...

REM Get the webhook URL from CloudFormation outputs
for /f "delims=" %%i in ('aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query "StackSummaries[?contains(StackName, 'cdk-pipelines-multi-branch')].StackName" --output text') do set STACK_NAME=%%i

if "%STACK_NAME%"=="" (
    echo Error: Could not find CDK pipeline stack. Make sure the stack is deployed.
    exit /b 1
)

for /f "delims=" %%i in ('aws cloudformation describe-stacks --stack-name "%STACK_NAME%" --query "Stacks[0].Outputs[?OutputKey=='GitHubWebhookURL'].OutputValue" --output text') do set WEBHOOK_URL=%%i

if "%WEBHOOK_URL%"=="" (
    echo Error: Webhook URL not found in stack outputs. Make sure GitHub webhook infrastructure is deployed.
    exit /b 1
)

echo Webhook URL: %WEBHOOK_URL%
echo.

echo Retrieving webhook secret from Secrets Manager...
for /f "delims=" %%i in ('aws secretsmanager get-secret-value --secret-id github-webhook-secret --query SecretString --output text') do set SECRET_JSON=%%i

REM Note: This requires jq or manual parsing. For simplicity, we'll show instructions
echo Webhook secret is stored in AWS Secrets Manager with ID: github-webhook-secret
echo.

echo GitHub Webhook Configuration
echo =============================
echo.
echo To configure the webhook in your GitHub repository:
echo.
echo 1. Go to your GitHub repository
echo 2. Navigate to Settings ^> Webhooks ^> Add webhook
echo 3. Configure the webhook with the following settings:
echo.
echo    Payload URL: %WEBHOOK_URL%
echo    Content type: application/json
echo.
echo 4. For the Secret, retrieve it from AWS Secrets Manager:
echo    aws secretsmanager get-secret-value --secret-id github-webhook-secret --query SecretString --output text
echo.
echo 5. Select individual events:
echo    - Branch or tag creation
echo    - Branch or tag deletion
echo    - Pushes (optional, for additional branch detection)
echo.
echo 6. Ensure 'Active' is checked
echo 7. Click 'Add webhook'
echo.
echo The webhook is now configured and will trigger pipeline creation/deletion for branches.
