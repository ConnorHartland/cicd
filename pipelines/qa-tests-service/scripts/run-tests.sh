#!/bin/bash
set -e

# Usage: ./scripts/run-tests.sh <TEST_ENV> <TEST_GROUP>
# Example: ./scripts/run-tests.sh test smoke

TEST_ENV="${1:-$TEST_ENV}"
TEST_GROUP="${2:-$TEST_GROUP}"

if [ -z "$TEST_ENV" ] || [ -z "$TEST_GROUP" ]; then
  echo "Error: TEST_ENV and TEST_GROUP are required"
  echo "Usage: ./scripts/run-tests.sh <TEST_ENV> <TEST_GROUP>"
  exit 1
fi

echo "=============================================="
echo "Running Playwright Tests"
echo "  Environment: $TEST_ENV"
echo "  Test Group:  $TEST_GROUP"
echo "=============================================="

# Copy environment config
SOURCE_PATH="/build/envs/ndp/.env-cmdrc.json"
DESTINATION_PATH="./.env-cmdrc.json"

if cp "$SOURCE_PATH" "$DESTINATION_PATH"; then
  echo "Copied env config from $SOURCE_PATH"
else
  echo "Failed to copy env config from $SOURCE_PATH"
  exit 1
fi

# Install dependencies
echo "Installing dependencies..."
npm ci || npm install

# Run tests
echo "Running: npm run browserstack:${TEST_ENV}:${TEST_GROUP}"
npm run "browserstack:${TEST_ENV}:${TEST_GROUP}"
