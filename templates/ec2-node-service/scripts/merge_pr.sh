#!/bin/bash
# merge_pr.sh
# Automatically merges the current PR to main after successful Production deployment

set -e

echo "=== Auto-Merge PR to Main ==="

# Verify we're in PR context
if [ -z "$BITBUCKET_PR_ID" ]; then
  echo "ERROR: Not in PR context - BITBUCKET_PR_ID not set"
  exit 1
fi

# Verify required variables
if [ -z "$BITBUCKET_WORKSPACE" ] || [ -z "$BITBUCKET_REPO_SLUG" ]; then
  echo "ERROR: Missing required Bitbucket variables (BITBUCKET_WORKSPACE or BITBUCKET_REPO_SLUG)"
  exit 1
fi

if [ -z "$BITBUCKET_API_TOKEN" ]; then
  echo "ERROR: BITBUCKET_API_TOKEN not set - cannot merge PR"
  exit 1
fi

echo "Merging PR #${BITBUCKET_PR_ID} in ${BITBUCKET_WORKSPACE}/${BITBUCKET_REPO_SLUG}..."

# Merge the PR using Bitbucket REST API
# Using merge_strategy: merge_commit to preserve release branch history
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -u "${BITBUCKET_EMAIL}:${BITBUCKET_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  "https://api.bitbucket.org/2.0/repositories/${BITBUCKET_WORKSPACE}/${BITBUCKET_REPO_SLUG}/pullrequests/${BITBUCKET_PR_ID}/merge" \
  -d '{
    "merge_strategy": "merge_commit",
    "close_source_branch": true
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
  echo "PR #${BITBUCKET_PR_ID} merged successfully!"
  echo "Main branch will now run tag-release pipeline."
elif [ "$HTTP_CODE" = "409" ]; then
  # 409 Conflict - PR might already be merged or has conflicts
  echo "WARNING: Could not merge PR (HTTP 409 - Conflict)"
  echo "This may indicate the PR was already merged or has merge conflicts."
  echo "Response: $BODY"
  exit 1
else
  echo "ERROR: Failed to merge PR (HTTP ${HTTP_CODE})"
  echo "Response: $BODY"
  exit 1
fi

echo "=== Auto-Merge Complete ==="
