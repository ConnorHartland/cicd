#!/bin/bash
# verify_deploy.sh
# Verifies deployment by waiting for ASG refresh and optionally triggering smoke tests

set -e

echo "=== Verifying Deployment ==="

#######################################
# CONFIGURATION
#######################################
ASG_REFRESH_TIMEOUT=${ASG_REFRESH_TIMEOUT:-600}  # 10 minutes
ASG_POLL_INTERVAL=${ASG_POLL_INTERVAL:-30}       # 30 seconds
SMOKE_TEST_TIMEOUT=${SMOKE_TEST_TIMEOUT:-600}    # 10 minutes

#######################################
# 1. WAIT FOR ASG REFRESH
#######################################
echo ""
echo "=== Waiting for ASG Refresh ==="
echo "ASG: $ASG_NAME"

# Get the most recent instance refresh
get_refresh_status() {
  aws autoscaling describe-instance-refreshes \
    --auto-scaling-group-name "$ASG_NAME" \
    --region us-east-1 \
    --max-records 1 \
    --query 'InstanceRefreshes[0].[Status,PercentageComplete]' \
    --output text
}

START_TIME=$(date +%s)
while true; do
  RESULT=$(get_refresh_status)
  STATUS=$(echo "$RESULT" | awk '{print $1}')
  PERCENT=$(echo "$RESULT" | awk '{print $2}')

  echo "Status: $STATUS ($PERCENT% complete)"

  case "$STATUS" in
    "Successful")
      echo "ASG refresh completed successfully"
      break
      ;;
    "Failed"|"Cancelled")
      echo "ERROR: ASG refresh $STATUS"
      exit 1
      ;;
    "Pending"|"InProgress")
      ELAPSED=$(($(date +%s) - START_TIME))
      if [ "$ELAPSED" -ge "$ASG_REFRESH_TIMEOUT" ]; then
        echo "ERROR: ASG refresh timed out after ${ASG_REFRESH_TIMEOUT}s"
        exit 1
      fi
      echo "Waiting ${ASG_POLL_INTERVAL}s..."
      sleep "$ASG_POLL_INTERVAL"
      ;;
    *)
      echo "Unknown status: $STATUS"
      sleep "$ASG_POLL_INTERVAL"
      ;;
  esac
done

#######################################
# 2. TRIGGER SMOKE TESTS (OPTIONAL)
#######################################
if [ -n "$SMOKE_TEST_REPO" ] && [ -n "$SMOKE_TEST_WORKSPACE" ]; then
  echo ""
  echo "=== Triggering Smoke Tests ==="
  echo "Repo: $SMOKE_TEST_WORKSPACE/$SMOKE_TEST_REPO"

  # Trigger pipeline in test repo
  TRIGGER_RESPONSE=$(curl -s -X POST \
    -u "${BITBUCKET_EMAIL}:${BITBUCKET_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.bitbucket.org/2.0/repositories/${SMOKE_TEST_WORKSPACE}/${SMOKE_TEST_REPO}/pipelines/" \
    -d "{
      \"target\": {
        \"type\": \"pipeline_ref_target\",
        \"ref_type\": \"branch\",
        \"ref_name\": \"main\"
      },
      \"variables\": [
        {\"key\": \"TEST_ENV\", \"value\": \"${ENV_SUFFIX}\"},
        {\"key\": \"TRIGGERED_BY\", \"value\": \"${BITBUCKET_REPO_SLUG}\"},
        {\"key\": \"TRIGGERED_COMMIT\", \"value\": \"${BITBUCKET_COMMIT}\"}
      ]
    }")

  PIPELINE_UUID=$(echo "$TRIGGER_RESPONSE" | jq -r '.uuid // empty')

  if [ -z "$PIPELINE_UUID" ]; then
    echo "ERROR: Failed to trigger smoke test pipeline"
    echo "$TRIGGER_RESPONSE" | jq '.' 2>/dev/null || echo "$TRIGGER_RESPONSE"
    exit 1
  fi

  echo "Triggered pipeline: $PIPELINE_UUID"

  # Poll for pipeline completion
  echo "Waiting for smoke tests to complete..."
  START_TIME=$(date +%s)

  while true; do
    PIPELINE_STATUS=$(curl -s \
      -u "${BITBUCKET_EMAIL}:${BITBUCKET_API_TOKEN}" \
      "https://api.bitbucket.org/2.0/repositories/${SMOKE_TEST_WORKSPACE}/${SMOKE_TEST_REPO}/pipelines/${PIPELINE_UUID}" \
      | jq -r '.state.name // "PENDING"')

    echo "Pipeline status: $PIPELINE_STATUS"

    case "$PIPELINE_STATUS" in
      "COMPLETED")
        # Check result
        PIPELINE_RESULT=$(curl -s \
          -u "${BITBUCKET_EMAIL}:${BITBUCKET_API_TOKEN}" \
          "https://api.bitbucket.org/2.0/repositories/${SMOKE_TEST_WORKSPACE}/${SMOKE_TEST_REPO}/pipelines/${PIPELINE_UUID}" \
          | jq -r '.state.result.name // "UNKNOWN"')

        echo "Pipeline result: $PIPELINE_RESULT"

        if [ "$PIPELINE_RESULT" = "SUCCESSFUL" ]; then
          echo "Smoke tests passed"
          break
        else
          echo "ERROR: Smoke tests failed with result: $PIPELINE_RESULT"
          exit 1
        fi
        ;;
      "FAILED"|"ERROR"|"STOPPED")
        echo "ERROR: Smoke test pipeline $PIPELINE_STATUS"
        exit 1
        ;;
      *)
        ELAPSED=$(($(date +%s) - START_TIME))
        if [ "$ELAPSED" -ge "$SMOKE_TEST_TIMEOUT" ]; then
          echo "ERROR: Smoke tests timed out after ${SMOKE_TEST_TIMEOUT}s"
          exit 1
        fi
        sleep 15
        ;;
    esac
  done
else
  echo ""
  echo "=== Skipping Smoke Tests (SMOKE_TEST_REPO not configured) ==="
fi

echo ""
echo "=== Deployment Verification Complete ==="
