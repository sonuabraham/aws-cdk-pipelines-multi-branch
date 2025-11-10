#!/bin/bash
# Script to help set up GitHub webhook configuration

set -e

echo "GitHub Webhook Setup Helper"
echo "============================"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed. Please install it first."
    exit 1
fi

# Get the webhook URL from CloudFormation outputs
echo "Retrieving webhook URL from CloudFormation..."
STACK_NAME=$(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query "StackSummaries[?contains(StackName, 'cdk-pipelines-multi-branch')].StackName" --output text | head -n 1)

if [ -z "$STACK_NAME" ]; then
    echo "Error: Could not find CDK pipeline stack. Make sure the stack is deployed."
    exit 1
fi

WEBHOOK_URL=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='GitHubWebhookURL'].OutputValue" --output text)

if [ -z "$WEBHOOK_URL" ]; then
    echo "Error: Webhook URL not found in stack outputs. Make sure GitHub webhook infrastructure is deployed."
    exit 1
fi

echo "Webhook URL: $WEBHOOK_URL"
echo ""

# Get the webhook secret
echo "Retrieving webhook secret from Secrets Manager..."
WEBHOOK_SECRET=$(aws secretsmanager get-secret-value --secret-id github-webhook-secret --query SecretString --output text | jq -r '.secret')

if [ -z "$WEBHOOK_SECRET" ]; then
    echo "Error: Could not retrieve webhook secret from Secrets Manager."
    exit 1
fi

echo "Webhook Secret: $WEBHOOK_SECRET"
echo ""

echo "GitHub Webhook Configuration"
echo "============================="
echo ""
echo "To configure the webhook in your GitHub repository:"
echo ""
echo "1. Go to your GitHub repository"
echo "2. Navigate to Settings > Webhooks > Add webhook"
echo "3. Configure the webhook with the following settings:"
echo ""
echo "   Payload URL: $WEBHOOK_URL"
echo "   Content type: application/json"
echo "   Secret: $WEBHOOK_SECRET"
echo ""
echo "4. Select individual events:"
echo "   - Branch or tag creation"
echo "   - Branch or tag deletion"
echo "   - Pushes (optional, for additional branch detection)"
echo ""
echo "5. Ensure 'Active' is checked"
echo "6. Click 'Add webhook'"
echo ""
echo "The webhook is now configured and will trigger pipeline creation/deletion for branches."
