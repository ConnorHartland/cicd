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
        'set -e',
        'echo Stopping ${WEBAPP_SERVICE}...',
        'systemctl stop ${WEBAPP_SERVICE} || true',
        'echo Downloading build from S3...',
        'aws s3 cp s3://${S3_BUCKET}/build.zip ${WEBAPP_DIR}/',
        'unzip -o ${WEBAPP_DIR}/build.zip -d ${WEBAPP_DIR}/',
        'echo Starting ${WEBAPP_SERVICE}...',
        'systemctl start ${WEBAPP_SERVICE}',
        'echo Deploy complete'
      ]" \
      --timeout-seconds 300 \
      --query 'Command.CommandId' \
      --output text)

    echo "SSM command started: $COMMAND_ID"

    # Wait for completion on all instances
    FIRST_INSTANCE="${INSTANCE_IDS%% *}"
    echo "Waiting for command to complete..."

    aws ssm wait command-executed \
      --command-id "$COMMAND_ID" \
      --instance-id "$FIRST_INSTANCE" \
      --region "$AWS_REGION"

    # Check results for all instances
    echo "Checking results..."
    FAILED=0
    for INSTANCE_ID in $INSTANCE_IDS; do
      STATUS=$(aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --query 'Status' \
        --output text 2>/dev/null || echo "Unknown")

      if [ "$STATUS" = "Success" ]; then
        echo "  ${INSTANCE_ID}: Success"
      else
        echo "  ${INSTANCE_ID}: ${STATUS}"
        FAILED=$((FAILED + 1))
      fi
    done

    if [ "$FAILED" -gt 0 ]; then
      echo "ERROR: ${FAILED} instance(s) failed"
      exit 1
    fi

    echo "SSM deploy completed successfully"
    ;;

  *)
    echo "ERROR: Unknown deploy method: ${DEPLOY_METHOD}"
    echo "Usage: $0 [refresh|ssm]"
    exit 1
    ;;
esac

echo "=== Deploy Complete ==="
