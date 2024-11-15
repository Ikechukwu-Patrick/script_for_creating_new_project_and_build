#!/bin/bash

error_exit() {
    echo "Error: $1"
    exit 1
}

prompt_user_input() {
    local prompt_message=$1
    read -rp "$prompt_message: " input
    echo "$input"
}

# Project Setup Variables
PROJECT_NAME="cloud-Project"
GITHUB_USERNAME="Ikechukwu-Patrick"
BRANCH_NAME="cloud-branch"
ACCESS_LEVEL="admin"

echo "Creating a new Java Spring Boot project..."
curl -s https://start.spring.io/starter.zip -d name="$PROJECT_NAME" -d type=maven-project -d language=java -d version=0.0.1 -o "$PROJECT_NAME.zip" || error_exit "Failed to download project."

if [ -d "$PROJECT_NAME" ]; then
    echo "Removing existing project folder $PROJECT_NAME..."
    rm -rf "$PROJECT_NAME" || error_exit "Failed to remove existing project folder."
fi

echo "Unzipping project files..."
unzip -q "$PROJECT_NAME.zip" -d "$PROJECT_NAME" || error_exit "Failed to unzip project files."
rm "$PROJECT_NAME.zip"

cd "$PROJECT_NAME" || error_exit "Failed to navigate to project directory."

echo "Initializing git repository..."
if [ -d ".git" ]; then
    echo "Git repository already exists. Skipping git init."
else
    git init || error_exit "Failed to initialize Git repository."
fi

# Check for uncommitted changes and make the initial commit
if [ -z "$(git status --porcelain)" ]; then
    echo "No changes to commit. Skipping initial commit."
else
    git add .
    git commit -m "Initial commit" || error_exit "Failed to commit initial files."
fi

echo "Checking if GitHub repository $PROJECT_NAME already exists..."
gh repo view "$GITHUB_USERNAME/$PROJECT_NAME" --json name -q .name 2>/dev/null

if [ $? -ne 0 ]; then
    echo "Repository does not exist. Proceeding to create it."
    gh repo create "$PROJECT_NAME" --public --source=. --remote=origin --push || error_exit "Failed to create GitHub repository."
else
    echo "Repository $PROJECT_NAME already exists."
    USE_EXISTING_REPO=$(prompt_user_input "Do you want to use the existing repository? (y/n)")
    if [ "$USE_EXISTING_REPO" == "y" ]; then
        echo "Using existing repository $PROJECT_NAME..."
    else
        PROJECT_NAME=$(prompt_user_input "Enter a new repository name")
        echo "Creating GitHub repository $PROJECT_NAME..."
        gh repo create "$PROJECT_NAME" --public --source=. --remote=origin --push || error_exit "Failed to create GitHub repository."
    fi
fi

echo "Setting default branch to master..."
gh repo edit "$GITHUB_USERNAME/$PROJECT_NAME" --default-branch master || error_exit "Failed to set default branch."

while true; do
    COLLABORATOR=$(prompt_user_input "Enter collaborator username (or type 'done' to finish)")
    if [ "$COLLABORATOR" == "done" ]; then
        break
    fi

    COLLABORATOR_EXISTS=$(gh api "/repos/$GITHUB_USERNAME/$PROJECT_NAME/collaborators/$COLLABORATOR" --silent --jq .login 2>/dev/null)

    if [ "$COLLABORATOR_EXISTS" == "$COLLABORATOR" ]; then
        echo "Collaborator $COLLABORATOR already exists. Skipping addition."
    else
        echo "Adding collaborator $COLLABORATOR with $ACCESS_LEVEL access..."
        gh api -X PUT "/repos/$GITHUB_USERNAME/$PROJECT_NAME/collaborators/$COLLABORATOR" -f permission="$ACCESS_LEVEL" || error_exit "Failed to add collaborator."
    fi
done

echo "Setting branch protection rules for master branch..."
gh api -X PUT "/repos/$GITHUB_USERNAME/$PROJECT_NAME/branches/master/protection" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    --input <(cat <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": []
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1
  },
  "restrictions": null
}
EOF
) || error_exit "Failed to set branch protection rules."

echo "Checking if branch $BRANCH_NAME exists..."
BRANCH_EXISTS=$(git ls-remote --heads origin "$BRANCH_NAME" | wc -l)

if [ "$BRANCH_EXISTS" -gt 0 ]; then
    echo "Branch $BRANCH_NAME already exists. Skipping branch creation."
else
    echo "Creating a new branch $BRANCH_NAME..."
    git checkout -b "$BRANCH_NAME" || error_exit "Failed to create branch."
    git push origin "$BRANCH_NAME" || error_exit "Failed to push branch to origin."
fi

echo "Setting up GitHub Actions workflow..."
mkdir -p .github/workflows
cat <<EOL > .github/workflows/ci.yml
name: CI

on:
  push:
    branches: ["$BRANCH_NAME"]
  pull_request:
    branches: ["$BRANCH_NAME"]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v2

    - name: Set up JDK 17
      uses: actions/setup-java@v1
      with:
        java-version: 17
        distribution: 'temurin'
    - name: Build with Maven
      run: mvn clean install -DskipTests
EOL

echo "Committing and pushing GitHub Actions workflow..."
if [ -z "$(git status --porcelain)" ]; then
    echo "No changes to commit for GitHub Actions workflow."
else
    git add .github/workflows/ci.yml
    git commit -m "Add GitHub Actions workflow for CI/CD" || error_exit "Failed to commit GitHub Actions workflow."
    git push origin "$BRANCH_NAME" || error_exit "Failed to push GitHub Actions workflow."
fi

echo "Project Setup Completed successfully! Check your GitHub Repository at https://github.com/$GITHUB_USERNAME/$PROJECT_NAME"
