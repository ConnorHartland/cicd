#!/bin/bash

# repos.sh - Clone repos organized by team and branch

declare -A REPOS=(
    # Format: ["team/repo-name"]="branch"
    ["backend/user-service"]="main"
    ["backend/auth-service"]="develop"
    ["backend/payment-service"]="main"
    ["frontend/web-app"]="develop"
    ["frontend/mobile-app"]="main"
    ["devops/infra-terraform"]="main"
    ["devops/pipeline-configs"]="develop"
)

BASE_URL="git@bitbucket.org:yourorg"  # Change to your git host
BASE_DIR="./repos"

for repo_path in "${!REPOS[@]}"; do
    branch="${REPOS[$repo_path]}"
    team="${repo_path%%/*}"
    repo="${repo_path##*/}"
    
    target_dir="$BASE_DIR/$team/$repo"
    
    if [[ -d "$target_dir" ]]; then
        echo "Skipping $repo (already exists)"
        continue
    fi
    
    echo "Cloning $repo ($branch) -> $target_dir"
    mkdir -p "$BASE_DIR/$team"
    git clone -b "$branch" "$BASE_URL/$repo.git" "$target_dir"
done

echo "Done!"