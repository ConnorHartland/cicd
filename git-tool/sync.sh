#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/repos.yaml"

WORKSPACE=$(yq '.workspace' "$CONFIG")
FOLDER=$(yq '.folder' "$CONFIG")
BRANCH=$(yq '.branch' "$CONFIG")

# Expand ~
FOLDER="${FOLDER/#\~/$HOME}"
mkdir -p "$FOLDER"

echo "Syncing to $FOLDER"

for repo in $(yq '.repos[]' "$CONFIG"); do
    echo "  $repo"
    if [ -d "$FOLDER/$repo" ]; then
        git -C "$FOLDER/$repo" fetch --all --prune
        git -C "$FOLDER/$repo" checkout "$BRANCH"
        git -C "$FOLDER/$repo" pull origin "$BRANCH"
    else
        git clone "git@bitbucket.org:${WORKSPACE}/${repo}.git" "$FOLDER/$repo"
        git -C "$FOLDER/$repo" checkout "$BRANCH"
    fi
done

echo "Done"
