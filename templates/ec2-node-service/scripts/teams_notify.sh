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
ENVIRONMENT="${ENV_SUFFIX:-unknown}"
ENVIRONMENT_UPPER=$(echo "$ENVIRONMENT" | tr '[:lower:]' '[:upper:]')
BRANCH="${BITBUCKET_BRANCH:-unknown}"
COMMIT="${BITBUCKET_COMMIT:0:7}"
TRIGGERED_BY="${BITBUCKET_STEP_TRIGGERER_UUID:-pipeline}"
PIPELINE_URL="https://bitbucket.org/${BITBUCKET_WORKSPACE}/${BITBUCKET_REPO_SLUG}/pipelines/results/${BITBUCKET_BUILD_NUMBER}"
TIMESTAMP=$(TZ='America/Chicago' date '+%Y-%m-%d %H:%M:%S CT')

# Determine card content based on status
case $STATUS in
  start)
    TITLE="🚀 Deployment Started"
    COLOR="accent"
    FACT_STATUS="In Progress"
    ;;
  success)
    TITLE="✅ Deployment Succeeded"
    COLOR="good"
    FACT_STATUS="Completed"
    ;;
  failure)
    TITLE="❌ Deployment Failed"
    COLOR="attention"
    FACT_STATUS="Failed"
    ;;
  *)
    TITLE="📋 Deployment Update"
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
  "commit": "${COMMIT}",
  "status": "${FACT_STATUS}",
  "timestamp": "${TIMESTAMP}",
  "pipelineUrl": "${PIPELINE_URL}"
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
