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

# Build deployment info from env vars
SERVICE_NAME="${BITBUCKET_REPO_SLUG:-unknown-service}"
WORKSPACE="${BITBUCKET_WORKSPACE:-unknown}"
ENVIRONMENT="${ENV_SUFFIX:-unknown}"
ENVIRONMENT_UPPER=$(echo "$ENVIRONMENT" | tr '[:lower:]' '[:upper:]')
BUILD_NUMBER="${BITBUCKET_BUILD_NUMBER:-0}"
TIMESTAMP=$(TZ='America/Chicago' date '+%Y-%m-%d %H:%M:%S CT')

# Defaults
BRANCH="${BITBUCKET_BRANCH:-unknown}"
COMMIT_SHORT="${BITBUCKET_COMMIT:0:7}"
COMMIT_FULL="${BITBUCKET_COMMIT:-unknown}"
COMMIT_MESSAGE=""
TRIGGERED_BY="pipeline"
TRIGGER_TYPE=""
DURATION=""

# Fetch pipeline info from Bitbucket API
if [ -n "$BITBUCKET_EMAIL" ] && [ -n "$BITBUCKET_API_TOKEN" ] && [ -n "$BITBUCKET_PIPELINE_UUID" ]; then
  echo "Fetching pipeline info from Bitbucket API..."
  PIPELINE_INFO=$(curl -s -u "${BITBUCKET_EMAIL}:${BITBUCKET_API_TOKEN}" \
    "https://api.bitbucket.org/2.0/repositories/${WORKSPACE}/${SERVICE_NAME}/pipelines/${BITBUCKET_PIPELINE_UUID}" 2>/dev/null || echo "{}")

  if [ -n "$PIPELINE_INFO" ] && [ "$PIPELINE_INFO" != "{}" ]; then
    # Debug: print raw API response (remove after debugging)
    echo "DEBUG: Pipeline API response:"
    echo "$PIPELINE_INFO" | head -c 2000
    echo ""

    # Extract creator display name
    CREATOR=$(echo "$PIPELINE_INFO" | grep -o '"creator"[[:space:]]*:[[:space:]]*{[^}]*}' | grep -o '"display_name"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    if [ -n "$CREATOR" ]; then
      TRIGGERED_BY="$CREATOR"
    fi

    # Extract trigger type (push, manual, schedule, etc.)
    TRIGGER_TYPE=$(echo "$PIPELINE_INFO" | grep -o '"trigger"[[:space:]]*:[[:space:]]*{[^}]*}' | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)

    # Extract commit message (nested under target.commit.message or top-level message)
    COMMIT_MSG=$(echo "$PIPELINE_INFO" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$COMMIT_MSG" ]; then
      # Truncate long messages and escape for JSON
      COMMIT_MESSAGE=$(echo "$COMMIT_MSG" | head -c 100 | tr '\n' ' ' | sed 's/"/\\"/g')
    fi

    # Extract duration if completed (API returns build_seconds_used)
    DURATION_SECS=$(echo "$PIPELINE_INFO" | grep -o '"build_seconds_used"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
    if [ -n "$DURATION_SECS" ] && [ "$DURATION_SECS" -gt 0 ]; then
      MINS=$((DURATION_SECS / 60))
      SECS=$((DURATION_SECS % 60))
      DURATION="${MINS}m ${SECS}s"
    fi
  fi
fi

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
    ICON="🚀"
    ;;
  success)
    TITLE="Deployment Succeeded"
    COLOR="good"
    FACT_STATUS="Completed"
    ICON="✅"
    ;;
  failure)
    TITLE="Deployment Failed"
    COLOR="attention"
    FACT_STATUS="Failed"
    ICON="❌"
    ;;
  *)
    TITLE="Deployment Update"
    COLOR="default"
    FACT_STATUS="$STATUS"
    ICON="📋"
    ;;
esac

# Combine triggered by with trigger type
if [ -n "$TRIGGER_TYPE" ]; then
  TRIGGERED_BY_FULL="${TRIGGERED_BY} (${TRIGGER_TYPE})"
else
  TRIGGERED_BY_FULL="${TRIGGERED_BY}"
fi

# Build the payload for Power Automate
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
  "commitMessage": "${COMMIT_MESSAGE}",
  "status": "${FACT_STATUS}",
  "timestamp": "${TIMESTAMP}",
  "buildNumber": "#${BUILD_NUMBER}",
  "themeColor": "${COLOR}",
  "repoUrl": "${REPO_URL}",
  "branchUrl": "${BRANCH_URL}",
  "commitUrl": "${COMMIT_URL}",
  "pipelineUrl": "${PIPELINE_URL}",
  "triggeredBy": "${TRIGGERED_BY}",
  "triggerType": "${TRIGGER_TYPE}",
  "triggeredByFull": "${TRIGGERED_BY_FULL}",
  "duration": "${DURATION}",
  "icon": "${ICON}"
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
