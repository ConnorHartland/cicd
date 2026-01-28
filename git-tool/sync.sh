#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/repos.yaml"

# Parse settings from YAML (requires yq - install with: brew install yq or apt install yq)
WORKSPACE=$(yq '.settings.workspace' "$CONFIG_FILE")
BASE_PATH=$(yq '.settings.base_path' "$CONFIG_FILE")
DEFAULT_BRANCH=$(yq '.settings.default_branch' "$CONFIG_FILE")

# Expand ~ in base path
BASE_PATH="${BASE_PATH/#\~/$HOME}"

echo "=== Git Repo Sync Tool ==="
echo "Workspace: $WORKSPACE"
echo "Base path: $BASE_PATH"
echo ""

# Iterate through each group
for group in $(yq '.groups | keys | .[]' "$CONFIG_FILE"); do
    folder=$(yq '.groups["'"$group"'"].folder' "$CONFIG_FILE")
    full_path="${BASE_PATH}/${folder}"

    echo "--- Group: $group ---"
    echo "Folder: $full_path"

    # Create folder if it doesn't exist
    mkdir -p "$full_path"

    # Get repo count for this group
    repo_count=$(yq '.groups["'"$group"'"].repos | length' "$CONFIG_FILE")

    for i in $(seq 0 $((repo_count - 1))); do
        repo_name=$(yq '.groups["'"$group"'"].repos['"$i"'].name' "$CONFIG_FILE")
        branch=$(yq '.groups["'"$group"'"].repos['"$i"'].branch' "$CONFIG_FILE")
        # Handle null/empty branch - fall back to default
        if [ "$branch" = "null" ] || [ -z "$branch" ]; then
            branch="$DEFAULT_BRANCH"
        fi

        repo_path="${full_path}/${repo_name}"
        repo_url="git@bitbucket.org:${WORKSPACE}/${repo_name}.git"

        echo ""
        echo "  Repo: $repo_name -> branch: $branch"

        if [ -d "$repo_path" ]; then
            echo "    Exists, fetching and switching to $branch..."
            cd "$repo_path"
            git fetch --all --prune
            git checkout "$branch"
            git pull origin "$branch"
            cd - > /dev/null
        else
            echo "    Cloning..."
            git clone "$repo_url" "$repo_path"
            cd "$repo_path"
            git checkout "$branch"
            cd - > /dev/null
        fi

        echo "    Done"
    done

    echo ""
done

echo "=== Sync complete ==="
