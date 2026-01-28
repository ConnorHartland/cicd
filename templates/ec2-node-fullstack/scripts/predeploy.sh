#!/bin/bash
# predeploy.sh
# Runs pre-deployment tasks: Kafka setup and Prisma migrations
#
# Required env vars: SERVICE_NAME, ENV_SUFFIX
# Optional env vars: ALLOW_TOPIC_RECREATE, SEED

set -e

if [ -z "$SERVICE_NAME" ] || [ -z "$ENV_SUFFIX" ]; then
  echo "Error: SERVICE_NAME and ENV_SUFFIX are required"
  exit 1
fi

echo "=== Pre-deploy: $SERVICE_NAME ($ENV_SUFFIX) ==="

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

  SPN=""
  KTAB=""

  # Database configuration per service and environment
  case "$ENV_SUFFIX" in
    "dev")
      case $SERVICE_NAME in
        # "my-service")
        #   export DATABASE_URL="sqlserver://HOST:PORT;database=DB;encrypt=true;integratedSecurity=true;trustServerCertificate=true;"
        #   SPN="MsSqlSvc/PRINCIPAL@DOMAIN"
        #   KTAB="/etc/krb5.keytab.myservicedev"
        #   ;;
        *)
          echo "Unknown service: $SERVICE_NAME for environment: $ENV_SUFFIX"
          exit 1
          ;;
      esac
      ;;
    "test"|"qa")
      case $SERVICE_NAME in
        *)
          echo "Unknown service: $SERVICE_NAME for environment: $ENV_SUFFIX"
          exit 1
          ;;
      esac
      ;;
    "prod")
      case $SERVICE_NAME in
        *)
          echo "Unknown service: $SERVICE_NAME for environment: $ENV_SUFFIX"
          exit 1
          ;;
      esac
      ;;
    *)
      echo "Invalid environment: $ENV_SUFFIX"
      exit 1
      ;;
  esac

  # Kerberos auth
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
