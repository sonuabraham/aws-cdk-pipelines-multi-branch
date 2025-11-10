#!/bin/bash

# Script to create or update GitHub personal access token in AWS Secrets Manager
# Usage: ./setup-github-token.sh --token <github_token> [--secret-name <secret_name>] [--region <region>]

set -e

# Default values
SECRET_NAME="github-personal-access-token"
REGION="ap-southeast-2"
GITHUB_TOKEN=""

# Parse command line arguments
while [ $# -gt 0 ]; do
   if [[ $1 == *"--"* ]]; then
        param="${1/--/}"
        declare $param="$2"
   fi
  shift
done

# Validate required parameters
if [[ -z "$token" ]]; then
  echo "Error: GitHub token is required"
  echo "Usage: ./setup-github-token.sh --token <github_token> [--secret-name <secret_name>] [--region <region>]"
  echo ""
  echo "Parameters:"
  echo "  --token         GitHub personal access token (required)"
  echo "  --secret-name   Secret name in AWS Secrets Manager (default: github-personal-access-token)"
  echo "  --region        AWS region (default: ap-southeast-2)"
  echo ""
  echo "Example:"
  echo "  ./setup-github-token.sh --token ghp_xxxxxxxxxxxx"
  exit 1
fi

GITHUB_TOKEN="$token"

# Use custom secret name if provided
if [[ -n "$secret_name" ]]; then
  SECRET_NAME="$secret_name"
fi

# Use custom region if provided
if [[ -n "$region" ]]; then
  REGION="$region"
fi

echo "Setting up GitHub token in AWS Secrets Manager..."
echo "Secret Name: $SECRET_NAME"
echo "Region: $REGION"

# Check if secret already exists
SECRET_EXISTS=$(aws secretsmanager describe-secret \
    --secret-id "$SECRET_NAME" \
    --region "$REGION" \
    2>/dev/null || echo "")

if [[ -n "$SECRET_EXISTS" ]]; then
    echo "Secret already exists. Updating secret value..."
    
    # Update existing secret
    aws secretsmanager put-secret-value \
        --secret-id "$SECRET_NAME" \
        --secret-string "$GITHUB_TOKEN" \
        --region "$REGION"
    
    echo "✓ GitHub token updated successfully in secret: $SECRET_NAME"
else
    echo "Secret does not exist. Creating new secret..."
    
    # Create new secret
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "GitHub personal access token for API calls" \
        --secret-string "$GITHUB_TOKEN" \
        --region "$REGION"
    
    echo "✓ GitHub token created successfully in secret: $SECRET_NAME"
fi

echo ""
echo "Next steps:"
echo "1. Update config.ini with: github_token_secret_name=$SECRET_NAME"
echo "2. Ensure your GitHub token has the following scopes:"
echo "   - repo (for private repositories)"
echo "   - public_repo (for public repositories)"
echo "3. Run initial-deploy.sh to deploy the pipeline"
echo ""
echo "Security reminder:"
echo "- Never commit your GitHub token to version control"
echo "- Rotate your token regularly"
echo "- Use the minimum required scopes for your token"

exit 0
