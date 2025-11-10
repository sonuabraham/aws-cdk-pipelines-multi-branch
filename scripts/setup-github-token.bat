@echo off
REM Script to create or update GitHub personal access token in AWS Secrets Manager
REM Usage: setup-github-token.bat --token <github_token> [--secret-name <secret_name>] [--region <region>]

setlocal enabledelayedexpansion

REM Default values
set SECRET_NAME=github-personal-access-token
set REGION=ap-southeast-2
set GITHUB_TOKEN=

REM Parse command line arguments
:parse_args
if "%~1"=="" goto validate_args
if "%~1"=="--token" set GITHUB_TOKEN=%~2& shift & shift & goto parse_args
if "%~1"=="--secret-name" set SECRET_NAME=%~2& shift & shift & goto parse_args
if "%~1"=="--region" set REGION=%~2& shift & shift & goto parse_args
shift
goto parse_args

:validate_args
if "%GITHUB_TOKEN%"=="" (
    echo Error: GitHub token is required
    echo Usage: setup-github-token.bat --token ^<github_token^> [--secret-name ^<secret_name^>] [--region ^<region^>]
    echo.
    echo Parameters:
    echo   --token         GitHub personal access token ^(required^)
    echo   --secret-name   Secret name in AWS Secrets Manager ^(default: github-personal-access-token^)
    echo   --region        AWS region ^(default: ap-southeast-2^)
    echo.
    echo Example:
    echo   setup-github-token.bat --token ghp_xxxxxxxxxxxx
    exit /b 1
)

echo Setting up GitHub token in AWS Secrets Manager...
echo Secret Name: %SECRET_NAME%
echo Region: %REGION%

REM Check if secret already exists
aws secretsmanager describe-secret --secret-id "%SECRET_NAME%" --region "%REGION%" >nul 2>&1
if %errorlevel% equ 0 (
    echo Secret already exists. Updating secret value...
    
    REM Update existing secret
    aws secretsmanager put-secret-value --secret-id "%SECRET_NAME%" --secret-string "%GITHUB_TOKEN%" --region "%REGION%"
    
    if %errorlevel% equ 0 (
        echo [32m✓ GitHub token updated successfully in secret: %SECRET_NAME%[0m
    ) else (
        echo [31mError: Failed to update secret[0m
        exit /b 1
    )
) else (
    echo Secret does not exist. Creating new secret...
    
    REM Create new secret
    aws secretsmanager create-secret --name "%SECRET_NAME%" --description "GitHub personal access token for API calls" --secret-string "%GITHUB_TOKEN%" --region "%REGION%"
    
    if %errorlevel% equ 0 (
        echo [32m✓ GitHub token created successfully in secret: %SECRET_NAME%[0m
    ) else (
        echo [31mError: Failed to create secret[0m
        exit /b 1
    )
)

echo.
echo Next steps:
echo 1. Update config.ini with: github_token_secret_name=%SECRET_NAME%
echo 2. Ensure your GitHub token has the following scopes:
echo    - repo ^(for private repositories^)
echo    - public_repo ^(for public repositories^)
echo 3. Run initial-deploy.sh to deploy the pipeline
echo.
echo Security reminder:
echo - Never commit your GitHub token to version control
echo - Rotate your token regularly
echo - Use the minimum required scopes for your token

endlocal
exit /b 0
