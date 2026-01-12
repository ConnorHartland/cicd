#!/bin/bash
set -e

echo "=== ValidateService: Running health checks ==="

# Wait for app to be ready
MAX_RETRIES=30
RETRY_INTERVAL=2
HEALTH_URL="http://localhost:3000/health"

for i in $(seq 1 $MAX_RETRIES); do
  echo "Health check attempt $i/$MAX_RETRIES..."

  if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
    echo "Health check passed!"

    # Verify PM2 process is running
    if pm2 list | grep -q "online"; then
      echo "PM2 process is online"
      echo "=== ValidateService complete ==="
      exit 0
    else
      echo "WARNING: PM2 process not showing as online"
    fi
  fi

  sleep $RETRY_INTERVAL
done

echo "ERROR: Health check failed after $MAX_RETRIES attempts"
exit 1
