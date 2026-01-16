#!/bin/bash
# newrelic_deploy.sh
# Posts a deployment marker to New Relic Change Tracking API

set -e

# Required: NEW_RELIC_API_KEY, NEW_RELIC_ENTITY_GUID
# Optional: NEW_RELIC_REGION (US or EU, defaults to US)

if [ -z "$NEW_RELIC_API_KEY" ] || [ -z "$NEW_RELIC_ENTITY_GUID" ]; then
  echo "NEW_RELIC_API_KEY or NEW_RELIC_ENTITY_GUID not set - skipping deployment marker"
  exit 0
fi

echo "=== Posting New Relic Deployment Marker ==="

# Determine API endpoint based on region
REGION="${NEW_RELIC_REGION:-US}"
if [ "$REGION" = "EU" ]; then
  API_ENDPOINT="https://api.eu.newrelic.com/graphql"
else
  API_ENDPOINT="https://api.newrelic.com/graphql"
fi

# Build deployment info
VERSION="${DEPLOY_VERSION:-${BITBUCKET_COMMIT:0:7}}"
DESCRIPTION="${DEPLOY_DESCRIPTION:-Deployed from ${BITBUCKET_BRANCH:-unknown} to ${ENV_SUFFIX:-unknown}}"
USER="${BITBUCKET_STEP_TRIGGERER_UUID:-${BITBUCKET_PIPELINE_UUID:-pipeline}}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Get commit message for changelog (truncate to 1000 chars)
CHANGELOG=""
if [ -n "$BITBUCKET_COMMIT" ]; then
  CHANGELOG=$(git log -1 --pretty=%B 2>/dev/null | head -c 1000 || echo "")
fi

# Escape strings for JSON
escape_json() {
  echo "$1" | jq -Rs '.[:-1]'
}

VERSION_JSON=$(escape_json "$VERSION")
DESCRIPTION_JSON=$(escape_json "$DESCRIPTION")
USER_JSON=$(escape_json "$USER")
CHANGELOG_JSON=$(escape_json "$CHANGELOG")

echo "Environment: ${ENV_SUFFIX:-unknown}"
echo "Version: ${VERSION}"
echo "Description: ${DESCRIPTION}"

# Build GraphQL mutation
MUTATION=$(cat << EOF
mutation {
  changeTrackingCreateDeployment(
    deployment: {
      version: ${VERSION_JSON}
      entityGuid: "${NEW_RELIC_ENTITY_GUID}"
      description: ${DESCRIPTION_JSON}
      user: ${USER_JSON}
      timestamp: ${TIMESTAMP}
      changelog: ${CHANGELOG_JSON}
      commit: "${BITBUCKET_COMMIT:-}"
      deepLink: "https://bitbucket.org/${BITBUCKET_WORKSPACE}/${BITBUCKET_REPO_SLUG}/pipelines/results/${BITBUCKET_BUILD_NUMBER}"
      deploymentType: BASIC
      groupId: "${BITBUCKET_REPO_SLUG:-app}"
    }
  ) {
    deploymentId
    entityGuid
  }
}
EOF
)

# Post to New Relic
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_ENDPOINT" \
  -H "Content-Type: application/json" \
  -H "API-Key: ${NEW_RELIC_API_KEY}" \
  -d "{\"query\": $(echo "$MUTATION" | jq -Rs .)}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
  # Check for GraphQL errors
  ERRORS=$(echo "$BODY" | jq -r '.errors // empty')
  if [ -n "$ERRORS" ] && [ "$ERRORS" != "null" ]; then
    echo "New Relic API returned errors:"
    echo "$BODY" | jq '.errors'
    exit 1
  fi

  DEPLOYMENT_ID=$(echo "$BODY" | jq -r '.data.changeTrackingCreateDeployment.deploymentId // "unknown"')
  echo "Deployment marker created successfully (ID: ${DEPLOYMENT_ID})"
else
  echo "Failed to create deployment marker (HTTP ${HTTP_CODE})"
  echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
  # Don't fail the pipeline for New Relic issues
  exit 0
fi

echo "=== New Relic Deployment Marker Complete ==="
