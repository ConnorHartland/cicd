#!/bin/bash
set -eo pipefail

echo "=== AfterInstall: Setting up application ==="

APP_DIR="/var/www/app"
cd "$APP_DIR"

# Get environment from instance tag
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

# Get Environment tag from instance
ENVIRONMENT=$(aws ec2 describe-tags \
  --region "$REGION" \
  --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=Environment" \
  --query "Tags[0].Value" --output text)

echo "Detected environment: $ENVIRONMENT"

# Pull environment-specific config from S3
# Update this bucket/path to match your setup
CONFIG_BUCKET="your-config-bucket"
CONFIG_PATH="${ENVIRONMENT}/.env"

echo "Fetching config from s3://${CONFIG_BUCKET}/${CONFIG_PATH}"
aws s3 cp "s3://${CONFIG_BUCKET}/${CONFIG_PATH}" .env

# Set ownership
chown -R ec2-user:ec2-user "$APP_DIR"

# Install production dependencies
echo "Installing dependencies..."
npm ci --production --ignore-scripts

echo "=== AfterInstall complete ==="
