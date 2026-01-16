#!/bin/bash
# prisma_migration.sh
# Runs Prisma database migrations with Kerberos authentication
# Usage: ./prisma_migration.sh <service> <environment> [seed]

set -e

SERVICE=${1:-$SERVICE_NAME}
APP_ENV=${2:-$ENV_SUFFIX}
SEED=${3:-false}

if [ -z "$SERVICE" ] || [ -z "$APP_ENV" ]; then
  echo "Error: SERVICE and APP_ENV are required"
  echo "Usage: ./prisma_migration.sh <service> <environment> [seed]"
  exit 1
fi

echo "Running Prisma migration for service: $SERVICE, environment: $APP_ENV"

SPN=""
KTAB=""

# Prisma engine paths (adjust based on your runner setup)
export PRISMA_QUERY_ENGINE_LIBRARY=${PRISMA_QUERY_ENGINE_LIBRARY:-~/engines/libquery_engine.so}
export PRISMA_SCHEMA_ENGINE_BINARY=${PRISMA_SCHEMA_ENGINE_BINARY:-~/engines/schema-engine}

# Database configuration per service and environment
# NOTE: Customize these values for your services
case "$APP_ENV" in
  "dev")
    case $SERVICE in
      # Add your service database configurations here
      # Example:
      # "my-api-service")
      #   export DATABASE_URL="sqlserver://DB_HOST:PORT;database=MyDB;encrypt=true;integratedSecurity=true;trustServerCertificate=true;"
      #   SPN="MsSqlSvc/SERVICE_PRINCIPAL@DOMAIN"
      #   KTAB="/etc/krb5.keytab.myservicedev"
      #   ;;
      *)
        echo "Unknown service: $SERVICE for environment: $APP_ENV"
        exit 1
        ;;
    esac
    ;;
  "test")
    case $SERVICE in
      *)
        echo "Unknown service: $SERVICE for environment: $APP_ENV"
        exit 1
        ;;
    esac
    ;;
  "qa")
    case $SERVICE in
      *)
        echo "Unknown service: $SERVICE for environment: $APP_ENV"
        exit 1
        ;;
    esac
    ;;
  "prod")
    case $SERVICE in
      *)
        echo "Unknown service: $SERVICE for environment: $APP_ENV"
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Invalid environment: $APP_ENV"
    echo "Valid environments: dev, test, qa, prod"
    exit 1
    ;;
esac

# Kerberos authentication
if [ -n "$SPN" ] && [ -n "$KTAB" ]; then
  echo "Authenticating with Kerberos..."
  /usr/bin/kdestroy 2>/dev/null || true
  /usr/bin/kinit -kt "$KTAB" "$SPN"
fi

# Run migrations
echo "Running Prisma migrations..."
npm run prisma:migration:deploy

echo "Generating Prisma client..."
npm run prisma:generate

# Seed database if requested (non-prod only)
if [ "$SEED" = "true" ]; then
  if [ "$APP_ENV" = "prod" ]; then
    echo "Warning: Skipping seed for production environment"
  else
    echo "Preparing and seeding database..."
    npm run prepare:test
    npm run prisma:seed
  fi
fi

echo "Prisma migration complete"
