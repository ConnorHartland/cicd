#!/bin/bash
# predeploy.sh
# Runs pre-deployment tasks: Kafka setup and Prisma migrations
#
# Required env vars: ENV_SUFFIX
# Optional env vars: ALLOW_TOPIC_RECREATE, SEED, DATABASE_URL, SPN, KTAB

set -e

if [ -z "$ENV_SUFFIX" ]; then
  echo "Error: ENV_SUFFIX is required"
  exit 1
fi

echo "=== Pre-deploy ($ENV_SUFFIX) ==="

# ===================
# KAFKA SETUP
# ===================
if [ -f "kafka.yml" ] || [ -f "kafka.yaml" ]; then
  echo ""
  echo "--- Kafka Setup ---"
  if [ "$ALLOW_TOPIC_RECREATE" = "true" ]; then
    echo "Topic recreation enabled"
    npm run kafka:setup -- --env=$ENV_SUFFIX --recreate
  else
    npm run kafka:setup -- --env=$ENV_SUFFIX
  fi
fi

# ===================
# PRISMA MIGRATION
# ===================
if [ -f "prisma/schema.prisma" ]; then
  echo ""
  echo "--- Prisma Migration ---"

  export PRISMA_QUERY_ENGINE_LIBRARY=${PRISMA_QUERY_ENGINE_LIBRARY:-~/engines/libquery_engine.so}
  export PRISMA_SCHEMA_ENGINE_BINARY=${PRISMA_SCHEMA_ENGINE_BINARY:-~/engines/schema-engine}

  # Kerberos auth if configured
  if [ -n "$SPN" ] && [ -n "$KTAB" ]; then
    echo "Authenticating with Kerberos..."
    /usr/bin/kdestroy 2>/dev/null || true
    /usr/bin/kinit -kt "$KTAB" "$SPN"
  fi

  echo "Running migrations..."
  npm run prisma:migration:deploy

  echo "Generating client..."
  npm run prisma:generate

  # Seed (non-prod only)
  if [ "$SEED" = "true" ] && [ "$ENV_SUFFIX" != "prod" ]; then
    echo "Seeding database..."
    npm run prepare:test
    npm run prisma:seed
  fi
fi

echo ""
echo "=== Pre-deploy complete ==="
