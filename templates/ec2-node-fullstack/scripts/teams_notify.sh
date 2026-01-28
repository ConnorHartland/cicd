#!/bin/bash
# teams_notify.sh
# Posts deployment notifications to Microsoft Teams via incoming webhook

set -e

STATUS="${1:-start}"

# Skip if webhook URL not configured
if [ -z "$TEAMS_WEBHOOK_URL" ]; then
  echo "TEAMS_WEBHOOK_URL not set - skipping Teams notification"
  exit 0
fi

echo "=== Sending Teams Notification (${STATUS}) ==="

# Build deployment info
SERVICE_NAME="${BITBUCKET_REPO_SLUG:-unknown-service}"
WORKSPACE="${BITBUCKET_WORKSPACE:-unknown}"
ENVIRONMENT="${ENV_SUFFIX:-unknown}"
ENVIRONMENT_UPPER=$(echo "$ENVIRONMENT" | tr '[:lower:]' '[:upper:]')
BRANCH="${BITBUCKET_BRANCH:-unknown}"
COMMIT_SHORT="${BITBUCKET_COMMIT:0:7}"
COMMIT_FULL="${BITBUCKET_COMMIT:-unknown}"
BUILD_NUMBER="${BITBUCKET_BUILD_NUMBER:-0}"

# Get user who triggered the pipeline
if [ -n "$BITBUCKET_STEP_TRIGGERER_UUID" ]; then
  # Try to get display name from Bitbucket API
  USER_INFO=$(curl -s -u "${BITBUCKET_USERNAME}:${BITBUCKET_APP_PASSWORD}" \
    "https://api.bitbucket.org/2.0/users/${BITBUCKET_STEP_TRIGGERER_UUID}" 2>/dev/null || echo "{}")
  TRIGGERED_BY=$(echo "$USER_INFO" | grep -o '"display_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
  if [ -z "$TRIGGERED_BY" ]; then
    TRIGGERED_BY="${BITBUCKET_STEP_TRIGGERER_UUID}"
  fi
else
  TRIGGERED_BY="pipeline"
fi
TIMESTAMP=$(TZ='America/Chicago' date '+%Y-%m-%d %H:%M:%S CT')

# Build URLs
REPO_URL="https://bitbucket.org/${WORKSPACE}/${SERVICE_NAME}"
BRANCH_URL="https://bitbucket.org/${WORKSPACE}/${SERVICE_NAME}/branch/${BRANCH}"
COMMIT_URL="https://bitbucket.org/${WORKSPACE}/${SERVICE_NAME}/commits/${COMMIT_FULL}"
PIPELINE_URL="https://bitbucket.org/${WORKSPACE}/${SERVICE_NAME}/pipelines/results/${BUILD_NUMBER}"

# Determine card content based on status
case $STATUS in
  start)
    TITLE="Deployment Started"
    COLOR="accent"
    FACT_STATUS="In Progress"
    ;;
  success)
    TITLE="Deployment Succeeded"
    COLOR="good"
    FACT_STATUS="Completed"
    ;;
  failure)
    TITLE="Deployment Failed"
    COLOR="attention"
    FACT_STATUS="Failed"
    ;;
  *)
    TITLE="Deployment Update"
    COLOR="default"
    FACT_STATUS="$STATUS"
    ;;
esac

# Build the payload for Power Automate
# Includes both the message wrapper AND flat properties for triggerBody() access
PAYLOAD=$(cat << EOF
{
  "type": "message",
  "attachments": [
    {
      "contentType": "application/vnd.microsoft.card.adaptive",
      "content": {}
    }
  ],
  "title": "${TITLE}",
  "serviceName": "${SERVICE_NAME}",
  "environment": "${ENVIRONMENT_UPPER}",
  "branch": "${BRANCH}",
  "commit": "${COMMIT_SHORT}",
  "status": "${FACT_STATUS}",
  "timestamp": "${TIMESTAMP}",
  "buildNumber": "#${BUILD_NUMBER}",
  "themeColor": "${COLOR}",
  "repoUrl": "${REPO_URL}",
  "branchUrl": "${BRANCH_URL}",
  "commitUrl": "${COMMIT_URL}",
  "pipelineUrl": "${PIPELINE_URL}",
  "triggeredBy": "${TRIGGERED_BY}"
}
EOF
)

# Post to Teams
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$TEAMS_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "202" ]; then
  echo "Teams notification sent successfully"
else
  echo "Failed to send Teams notification (HTTP ${HTTP_CODE})"
  echo "$BODY"
  # Don't fail the pipeline for notification issues
fi

echo "=== Teams Notification Complete ==="
