#!/bin/bash
# deploy_asg.sh - Deploy to ASG via instance refresh or SSM
# Usage: ./deploy_asg.sh [refresh|ssm]
#
# Required env vars:
#   ASG_NAME       - Auto Scaling Group name
#   S3_BUCKET      - S3 bucket for build artifacts
#   AWS_REGION     - AWS region (default: us-east-1)
#
# Optional env vars:
#   INSTANCE_WARMUP - Seconds for instance warmup (default: 300)
#   WEBAPP_SERVICE  - Systemd service name (default: webapp)
#   WEBAPP_DIR      - App install directory (default: /opt/webapp)

set -e

DEPLOY_METHOD="${1:-refresh}"
AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_WARMUP="${INSTANCE_WARMUP:-300}"
WEBAPP_SERVICE="${WEBAPP_SERVICE:-webapp}"
WEBAPP_DIR="${WEBAPP_DIR:-/opt/webapp}"

if [ -z "$ASG_NAME" ] || [ -z "$S3_BUCKET" ]; then
  echo "ERROR: ASG_NAME and S3_BUCKET must be set"
  exit 1
fi

echo "=== Deploying to ${ASG_NAME} via ${DEPLOY_METHOD} ==="

case $DEPLOY_METHOD in
  refresh)
    # Instance refresh - rolling update via ASG (fire and forget)
    echo "Starting instance refresh..."

    PREFERENCES="{\"InstanceWarmup\": ${INSTANCE_WARMUP}}"
    REFRESH_ID=$(aws autoscaling start-instance-refresh \
      --region "$AWS_REGION" \
      --auto-scaling-group-name "$ASG_NAME" \
      --preferences "$PREFERENCES" \
      --query 'InstanceRefreshId' \
      --output text)

    echo "Instance refresh started: $REFRESH_ID"
    echo "ASG will handle rolling replacement in the background"
    ;;

  ssm)
    # SSM deploy - push directly to running instances
    echo "Getting InService instances from ASG..."

    INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
      --region "$AWS_REGION" \
      --auto-scaling-group-names "$ASG_NAME" \
      --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
      --output text)

    if [ -z "$INSTANCE_IDS" ]; then
      echo "ERROR: No InService instances found in ${ASG_NAME}"
      exit 1
    fi

    INSTANCE_COUNT=$(echo "$INSTANCE_IDS" | wc -w)
    echo "Found ${INSTANCE_COUNT} instance(s): ${INSTANCE_IDS}"

    # Send deploy command via SSM
    echo "Sending deploy command..."
    COMMAND_ID=$(aws ssm send-command \
      --region "$AWS_REGION" \
      --instance-ids $INSTANCE_IDS \
      --document-name "AWS-RunShellScript" \
      --parameters "commands=[
        'echo === Starting deployment ===',
        'systemctl stop ${WEBAPP_SERVICE} 2>/dev/null || echo Service was not running',
        'echo Downloading build from S3...',
        'aws s3 cp s3://${S3_BUCKET}/build.zip ${WEBAPP_DIR}/',
        'echo Extracting build...',
        'cd ${WEBAPP_DIR} && unzip -o build.zip',
        'echo Starting ${WEBAPP_SERVICE}...',
        'systemctl start ${WEBAPP_SERVICE}',
        'sleep 2',
        'systemctl is-active ${WEBAPP_SERVICE} && echo === Deploy successful ==='
      ]" \
      --timeout-seconds 300 \
      --query 'Command.CommandId' \
      --output text)

    echo "SSM command started: $COMMAND_ID"

    # Poll for completion instead of using waiter (more control)
    echo "Waiting for command to complete..."
    WAIT_TIMEOUT=300
    ELAPSED=0
    while [ "$ELAPSED" -lt "$WAIT_TIMEOUT" ]; do
      sleep 10
      ELAPSED=$((ELAPSED + 10))

      # Check command status
      CMD_STATUS=$(aws ssm list-commands \
        --region "$AWS_REGION" \
        --command-id "$COMMAND_ID" \
        --query 'Commands[0].Status' \
        --output text 2>/dev/null || echo "Pending")

      echo "  Command status: $CMD_STATUS (${ELAPSED}s)"

      if [ "$CMD_STATUS" = "Success" ]; then
        break
      elif [ "$CMD_STATUS" = "Failed" ] || [ "$CMD_STATUS" = "Cancelled" ] || [ "$CMD_STATUS" = "TimedOut" ]; then
        echo "Command finished with status: $CMD_STATUS"
        break
      fi
    done

    # Check results and output for all instances
    echo ""
    echo "=== Instance Results ==="
    FAILED=0
    for INSTANCE_ID in $INSTANCE_IDS; do
      INVOCATION=$(aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --output json 2>/dev/null || echo "{}")

      STATUS=$(echo "$INVOCATION" | grep -o '"Status"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
      STATUS=${STATUS:-Unknown}

      echo ""
      echo "Instance: $INSTANCE_ID - $STATUS"

      # Show output for debugging
      STDOUT=$(echo "$INVOCATION" | grep -o '"StandardOutputContent"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4 | head -c 500)
      STDERR=$(echo "$INVOCATION" | grep -o '"StandardErrorContent"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4 | head -c 500)

      if [ -n "$STDOUT" ]; then
        echo "  Output: $STDOUT"
      fi
      if [ -n "$STDERR" ]; then
        echo "  Errors: $STDERR"
      fi

      if [ "$STATUS" != "Success" ]; then
        FAILED=$((FAILED + 1))
      fi
    done

    echo ""
    if [ "$FAILED" -gt 0 ]; then
      echo "WARNING: ${FAILED} instance(s) reported non-success status"
      echo "Check output above - deployment may still have succeeded"
      # Don't exit 1 here - let verify_deploy health check determine success
    fi

    echo "SSM deploy completed"
    ;;

  *)
    echo "ERROR: Unknown deploy method: ${DEPLOY_METHOD}"
    echo "Usage: $0 [refresh|ssm]"
    exit 1
    ;;
esac

echo "=== Deploy Complete ==="
