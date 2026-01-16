#!/bin/bash
# setup_kafka.sh
# Sets up Kafka topics based on kafka.yml in the service repo
# Uses npm scripts defined in the service's package.json

set -e

ENV_SUFFIX=${1:-$ENV_SUFFIX}
ALLOW_TOPIC_RECREATE=${2:-$ALLOW_TOPIC_RECREATE}

if [ -z "$ENV_SUFFIX" ]; then
  echo "Error: ENV_SUFFIX is required"
  exit 1
fi

echo "Setting up Kafka topics for environment: $ENV_SUFFIX"

if [ "$ALLOW_TOPIC_RECREATE" = "true" ]; then
  echo "Topic recreation is enabled"
  npm run kafka:setup -- --env=$ENV_SUFFIX --recreate
else
  npm run kafka:setup -- --env=$ENV_SUFFIX
fi

echo "Kafka setup complete"
