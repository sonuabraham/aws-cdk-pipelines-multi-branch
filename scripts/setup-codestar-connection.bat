@echo off
REM Script to create AWS CodeStar Connection for GitHub
REM Usage: setup-codestar-connection.bat --connection-name <name> [--region <region>]

setlocal enabledelayedexpansion

REM Default values
set CONNECTION_NAME=github-connection
set REGION=ap-southeast-2

REM Parse command line arguments
:parse_args
if "%~1"=="" goto setup_connection
if "%~1"=="--connection-name" set CONNECTION_NAME=%~2& shift & shift & goto parse_args
if "%~1"=="--region" set REGION=%~2& shift & shift & goto parse_args
shift
goto parse_args

:setup_connection
echo ==========================================
echo AWS CodeStar Connection Setup for GitHub
echo ==========================================
echo.
echo Connection Name: %CONNECTION_NAME%
echo Region: %REGION%
echo.

REM Check if connection already exists
echo Checking if connection already exists...

REM Create temp file for JSON output
set TEMP_FILE=%TEMP%\codestar_connections_%RANDOM%.json
aws codestar-connections list-connections --region "%REGION%" --output json > "%TEMP_FILE%" 2>nul

if %errorlevel% neq 0 (
    echo Error: Failed to list connections. Check AWS CLI configuration.
    del "%TEMP_FILE%" 2>nul
    exit /b 1
)

REM Check if jq is available
where jq >nul 2>&1
if %errorlevel% neq 0 (
    echo Warning: jq not found. Skipping duplicate check.
    echo If connection exists, you'll see an error below.
    goto create_connection
)

REM Parse JSON to find existing connection
for /f "delims=" %%i in ('jq -r ".Connections[] | select(.ConnectionName==\"%CONNECTION_NAME%\") | .ConnectionArn" "%TEMP_FILE%"') do set EXISTING_CONNECTION=%%i

if not "!EXISTING_CONNECTION!"=="" if not "!EXISTING_CONNECTION!"=="null" (
    echo Warning: Connection already exists!
    echo Connection ARN: !EXISTING_CONNECTION!
    echo.
    
    REM Get connection status
    set STATUS_FILE=%TEMP%\connection_status_%RANDOM%.json
    aws codestar-connections get-connection --connection-arn "!EXISTING_CONNECTION!" --region "%REGION%" --output json > "!STATUS_FILE!" 2>nul
    
    for /f "delims=" %%s in ('jq -r ".Connection.ConnectionStatus" "!STATUS_FILE!"') do set CONNECTION_STATUS=%%s
    
    echo Connection Status: !CONNECTION_STATUS!
    echo.
    
    if "!CONNECTION_STATUS!"=="AVAILABLE" (
        echo [32m✓ Connection is already authorized and ready to use![0m
        echo.
        echo Connection ARN: !EXISTING_CONNECTION!
        echo.
        echo Next steps:
        echo 1. Update config.ini with: github_connection_arn=!EXISTING_CONNECTION!
        echo 2. Configure github_owner and github_repo in config.ini
        echo 3. Run initial-deploy.sh to deploy the pipeline
    ) else (
        echo [33m⚠ Connection exists but is not authorized (Status: !CONNECTION_STATUS!^)[0m
        echo.
        echo To authorize the connection:
        echo 1. Open the AWS Console: https://console.aws.amazon.com/codesuite/settings/connections
        echo 2. Find connection: %CONNECTION_NAME%
        echo 3. Click 'Update pending connection'
        echo 4. Follow the GitHub authorization flow
        echo 5. Once authorized, update config.ini with: github_connection_arn=!EXISTING_CONNECTION!
    )
    
    del "%TEMP_FILE%" 2>nul
    del "!STATUS_FILE!" 2>nul
    exit /b 0
)

:create_connection
del "%TEMP_FILE%" 2>nul

REM Create new connection
echo Creating new CodeStar Connection...
echo.

set CREATE_FILE=%TEMP%\create_connection_%RANDOM%.json
aws codestar-connections create-connection --connection-name "%CONNECTION_NAME%" --provider-type GitHub --region "%REGION%" --output json > "%CREATE_FILE%"

if %errorlevel% neq 0 (
    echo [31m❌ Error: Failed to create connection[0m
    del "%CREATE_FILE%" 2>nul
    exit /b 1
)

REM Parse connection ARN
where jq >nul 2>&1
if %errorlevel% neq 0 (
    echo [31mError: jq is required to parse the connection ARN[0m
    echo Please install jq from: https://stedolan.github.io/jq/download/
    del "%CREATE_FILE%" 2>nul
    exit /b 1
)

for /f "delims=" %%a in ('jq -r ".ConnectionArn" "%CREATE_FILE%"') do set CONNECTION_ARN=%%a

if "!CONNECTION_ARN!"=="" (
    echo [31m❌ Error: Failed to create connection[0m
    del "%CREATE_FILE%" 2>nul
    exit /b 1
)

del "%CREATE_FILE%" 2>nul

echo [32m✓ Connection created successfully![0m
echo.
echo Connection ARN: !CONNECTION_ARN!
echo.
echo ==========================================
echo IMPORTANT: Manual Authorization Required
echo ==========================================
echo.
echo The connection has been created but requires manual authorization in the AWS Console.
echo.
echo Steps to authorize:
echo.
echo 1. Open the AWS Console:
echo    https://console.aws.amazon.com/codesuite/settings/connections?region=%REGION%
echo.
echo 2. Find your connection:
echo    Name: %CONNECTION_NAME%
echo    Status: PENDING
echo.
echo 3. Click 'Update pending connection'
echo.
echo 4. Click 'Install a new app' or select an existing GitHub App
echo.
echo 5. Authorize AWS Connector for GitHub:
echo    - Select your GitHub account or organization
echo    - Choose which repositories to grant access to
echo    - Click 'Install' or 'Install ^& Authorize'
echo.
echo 6. Complete the authorization in the AWS Console
echo.
echo 7. Verify the connection status changes to 'Available'
echo.
echo ==========================================
echo Configuration
echo ==========================================
echo.
echo After authorization is complete, add this to your config.ini:
echo.
echo [general]
echo github_owner=your-github-username
echo github_repo=your-repo-name
echo github_connection_arn=!CONNECTION_ARN!
echo.
echo ==========================================
echo Next Steps
echo ==========================================
echo.
echo 1. Authorize the connection in AWS Console (see steps above^)
echo 2. Update config.ini with the connection ARN and repository details
echo 3. Optionally set up GitHub token for API calls:
echo    scripts\setup-github-token.bat --token ^<your_token^>
echo 4. Run initial-deploy.sh to deploy the pipeline
echo.
echo For more information, see docs/quick-start-github.md
echo.

endlocal
exit /b 0
