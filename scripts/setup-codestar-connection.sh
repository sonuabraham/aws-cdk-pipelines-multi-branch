#!/bin/bash

# Script to create AWS CodeStar Connection for GitHub
# Usage: ./setup-codestar-connection.sh --connection-name <name> [--region <region>]

set -e

# Default values
CONNECTION_NAME="github-connection"
REGION="ap-southeast-2"

# Parse command line arguments
while [ $# -gt 0 ]; do
   if [[ $1 == *"--"* ]]; then
        param="${1/--/}"
        declare $param="$2"
   fi
  shift
done

# Use custom connection name if provided
if [[ -n "$connection_name" ]]; then
  CONNECTION_NAME="$connection_name"
fi

# Use custom region if provided
if [[ -n "$region" ]]; then
  REGION="$region"
fi

echo "=========================================="
echo "AWS CodeStar Connection Setup for GitHub"
echo "=========================================="
echo ""
echo "Connection Name: $CONNECTION_NAME"
echo "Region: $REGION"
echo ""

# Check if connection already exists
echo "Checking if connection already exists..."
EXISTING_CONNECTION=$(aws codestar-connections list-connections \
    --region "$REGION" \
    --output json 2>/dev/null | \
    jq -r ".Connections[] | select(.ConnectionName==\"$CONNECTION_NAME\") | .ConnectionArn" || echo "")

if [[ -n "$EXISTING_CONNECTION" ]]; then
    echo "⚠ Connection already exists!"
    echo "Connection ARN: $EXISTING_CONNECTION"
    echo ""
    
    # Get connection status
    CONNECTION_STATUS=$(aws codestar-connections get-connection \
        --connection-arn "$EXISTING_CONNECTION" \
        --region "$REGION" \
        --output json | jq -r '.Connection.ConnectionStatus')
    
    echo "Connection Status: $CONNECTION_STATUS"
    echo ""
    
    if [[ "$CONNECTION_STATUS" == "AVAILABLE" ]]; then
        echo "✓ Connection is already authorized and ready to use!"
        echo ""
        echo "Connection ARN: $EXISTING_CONNECTION"
        echo ""
        echo "Next steps:"
        echo "1. Update config.ini with: github_connection_arn=$EXISTING_CONNECTION"
        echo "2. Configure github_owner and github_repo in config.ini"
        echo "3. Run initial-deploy.sh to deploy the pipeline"
    else
        echo "⚠ Connection exists but is not authorized (Status: $CONNECTION_STATUS)"
        echo ""
        echo "To authorize the connection:"
        echo "1. Open the AWS Console: https://console.aws.amazon.com/codesuite/settings/connections"
        echo "2. Find connection: $CONNECTION_NAME"
        echo "3. Click 'Update pending connection'"
        echo "4. Follow the GitHub authorization flow"
        echo "5. Once authorized, update config.ini with: github_connection_arn=$EXISTING_CONNECTION"
    fi
    
    exit 0
fi

# Create new connection
echo "Creating new CodeStar Connection..."
echo ""

CREATE_OUTPUT=$(aws codestar-connections create-connection \
    --connection-name "$CONNECTION_NAME" \
    --provider-type GitHub \
    --region "$REGION" \
    --output json)

CONNECTION_ARN=$(echo "$CREATE_OUTPUT" | jq -r '.ConnectionArn')

if [[ -z "$CONNECTION_ARN" || "$CONNECTION_ARN" == "null" ]]; then
    echo "❌ Error: Failed to create connection"
    exit 1
fi

echo "✓ Connection created successfully!"
echo ""
echo "Connection ARN: $CONNECTION_ARN"
echo ""
echo "=========================================="
echo "IMPORTANT: Manual Authorization Required"
echo "=========================================="
echo ""
echo "The connection has been created but requires manual authorization in the AWS Console."
echo ""
echo "Steps to authorize:"
echo ""
echo "1. Open the AWS Console:"
echo "   https://console.aws.amazon.com/codesuite/settings/connections?region=$REGION"
echo ""
echo "2. Find your connection:"
echo "   Name: $CONNECTION_NAME"
echo "   Status: PENDING"
echo ""
echo "3. Click 'Update pending connection'"
echo ""
echo "4. Click 'Install a new app' or select an existing GitHub App"
echo ""
echo "5. Authorize AWS Connector for GitHub:"
echo "   - Select your GitHub account or organization"
echo "   - Choose which repositories to grant access to"
echo "   - Click 'Install' or 'Install & Authorize'"
echo ""
echo "6. Complete the authorization in the AWS Console"
echo ""
echo "7. Verify the connection status changes to 'Available'"
echo ""
echo "=========================================="
echo "Configuration"
echo "=========================================="
echo ""
echo "After authorization is complete, add this to your config.ini:"
echo ""
echo "[general]"
echo "github_owner=your-github-username"
echo "github_repo=your-repo-name"
echo "github_connection_arn=$CONNECTION_ARN"
echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Authorize the connection in AWS Console (see steps above)"
echo "2. Update config.ini with the connection ARN and repository details"
echo "3. Optionally set up GitHub token for API calls:"
echo "   ./scripts/setup-github-token.sh --token <your_token>"
echo "4. Run initial-deploy.sh to deploy the pipeline"
echo ""
echo "For more information, see docs/quick-start-github.md"
echo ""

exit 0
