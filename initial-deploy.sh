#!/bin/bash

#Including .ini file
. ./config.ini
echo ${region}
echo ${repository_name}

while [ $# -gt 0 ]; do
   if [[ $1 == *"--"* ]]; then
        param="${1/--/}"
        declare $param="$2"
   fi
  shift
done

if [[ -z "$dev_account_id" || -z "$dev_profile_name" || -z "$prod_account_id" || -z "$prod_profile_name" ]]; then
  echo "The following parameters are required: --dev_account_id, --dev_profile_name, --prod_account_id, --prod_profile_name"
  exit
fi

echo "Dev account id: $dev_account_id"
echo "Dev profile name: $dev_profile_name"
echo "Prod account id: $prod_account_id"
echo "Prod profile name: $prod_profile_name"
echo "Region: $region"
echo "Repository name: $repository_name"

export DEV_ACCOUNT_ID=$dev_account_id
export PROD_ACCOUNT_ID=$prod_account_id

# retrieve default branch
export repository_name=cdk-pipelines-multi-branch
export region="ap-southeast-2"

# Check if GitHub configuration is present
if [[ -n "$github_owner" && -n "$github_repo" ]]; then
    echo "GitHub configuration detected. Using GitHub as source repository."
    echo "GitHub Owner: $github_owner"
    echo "GitHub Repo: $github_repo"
    
    # Retrieve GitHub token from AWS Secrets Manager if configured
    GITHUB_TOKEN=""
    if [[ -n "$github_token_secret_name" ]]; then
        echo "Retrieving GitHub token from AWS Secrets Manager..."
        GITHUB_TOKEN=$(aws secretsmanager get-secret-value \
            --secret-id "$github_token_secret_name" \
            --region "$region" \
            --query 'SecretString' \
            --output text 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            echo "Warning: Failed to retrieve GitHub token from Secrets Manager. Proceeding without authentication."
            echo "Note: Unauthenticated requests have lower rate limits (60 requests/hour)."
            GITHUB_TOKEN=""
        else
            echo "GitHub token retrieved successfully."
        fi
    else
        echo "No GitHub token configured. Using unauthenticated API requests."
        echo "Note: Unauthenticated requests have lower rate limits (60 requests/hour)."
    fi
    
    # Call GitHub API to get default branch
    echo "Fetching default branch from GitHub API..."
    if [[ -n "$GITHUB_TOKEN" ]]; then
        GITHUB_RESPONSE=$(curl -s -w "\n%{http_code}" \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$github_owner/$github_repo")
    else
        GITHUB_RESPONSE=$(curl -s -w "\n%{http_code}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$github_owner/$github_repo")
    fi
    
    # Extract HTTP status code (last line) and response body (all but last line)
    HTTP_CODE=$(echo "$GITHUB_RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$GITHUB_RESPONSE" | sed '$d')
    
    # Handle GitHub API errors
    if [ "$HTTP_CODE" -eq 200 ]; then
        export BRANCH=$(echo "$RESPONSE_BODY" | jq -r '.default_branch // empty')
        
        if [ -z "$BRANCH" ]; then
            echo "Error: Could not parse default branch from GitHub API response."
            exit 1
        fi
        
        echo "GitHub default branch detected: $BRANCH"
    elif [ "$HTTP_CODE" -eq 401 ]; then
        echo "Error: GitHub authentication failed (HTTP 401)."
        echo "Please check your GitHub token configuration."
        exit 1
    elif [ "$HTTP_CODE" -eq 403 ]; then
        # Check if it's a rate limit error
        if echo "$RESPONSE_BODY" | grep -q "rate limit"; then
            echo "Error: GitHub API rate limit exceeded (HTTP 403)."
            echo "Please configure a GitHub personal access token to increase rate limits."
            echo "Set 'github_token_secret_name' in config.ini and store the token in AWS Secrets Manager."
        else
            echo "Error: GitHub API access forbidden (HTTP 403)."
            echo "Please check repository permissions and token scopes."
        fi
        exit 1
    elif [ "$HTTP_CODE" -eq 404 ]; then
        echo "Error: GitHub repository not found (HTTP 404)."
        echo "Repository: $github_owner/$github_repo"
        echo "Please check the repository name and access permissions."
        exit 1
    else
        echo "Error: GitHub API request failed with HTTP status $HTTP_CODE"
        echo "Response: $RESPONSE_BODY"
        exit 1
    fi
    
elif [[ -n "$repository_name" ]]; then
    echo "CodeCommit configuration detected. Using CodeCommit as source repository."
    echo "Repository name: $repository_name"
    
    # Fallback to CodeCommit API
    export BRANCH=$(aws codecommit get-repository \
        --repository-name ${repository_name} \
        --region ${region} \
        --output json | jq -r '.repositoryMetadata.defaultBranch // empty')
    
    if [ -z "$BRANCH" ]; then
        echo "No default branch found. Trying to find the first available branch..."
        export BRANCH=$(aws codecommit list-branches \
            --repository-name ${repository_name} \
            --region ${region} \
            --output json | jq -r '.branches[0] // empty')
    fi
    
    if [ -z "$BRANCH" ]; then
        echo "No branches found. Ensure the repository has at least one commit."
        exit 1
    fi
    
    echo "CodeCommit branch detected: $BRANCH"
else
    echo "Error: No repository configuration found."
    echo "Please configure either GitHub (github_owner, github_repo) or CodeCommit (repository_name) in config.ini"
    exit 1
fi

echo "Using branch: $BRANCH"


# bootstrap Development AWS Account
#npx cdk bootstrap --profile $dev_profile_name --cloudformation-execution-policies arn:aws:iam::aws:policy/AdministratorAccess aws://$dev_account_id/${region}

# bootstrap Production AWS Account and add trust to development account where pipeline resides
#npx cdk bootstrap --profile $prod_profile_name --trust $dev_account_id --cloudformation-execution-policies arn:aws:iam::aws:policy/AdministratorAccess aws://$prod_account_id/${region}

# deploy pipeline
cdk deploy cdk-pipelines-multi-branch-$BRANCH

exit $?

