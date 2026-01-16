#!/bin/bash
# build_client.sh
# Builds React client with environment variable injection
# Called from the pipeline after npm ci in the client directory

set -e

echo "=== Building React Client ==="

CLIENT_DIR="${CLIENT_DIR:-client}"

# Verify client directory exists
if [ ! -d "$CLIENT_DIR" ]; then
  echo "ERROR: Client directory '$CLIENT_DIR' not found"
  exit 1
fi

#######################################
# INJECT ENVIRONMENT VARIABLES
#######################################
echo ""
echo "=== Injecting Environment Variables ==="

# Clear any existing .env file
> "$CLIENT_DIR/.env"

# Method 1: Inject all REACT_APP_* variables from environment
echo "Looking for REACT_APP_* variables..."
INJECTED_COUNT=0

while IFS='=' read -r name value; do
  if [[ $name == REACT_APP_* ]]; then
    echo "${name}=${value}" >> "$CLIENT_DIR/.env"
    echo "  + ${name}"
    ((INJECTED_COUNT++))
  fi
done < <(env)

# Method 2: Also support VITE_* for Vite-based React apps
while IFS='=' read -r name value; do
  if [[ $name == VITE_* ]]; then
    echo "${name}=${value}" >> "$CLIENT_DIR/.env"
    echo "  + ${name}"
    ((INJECTED_COUNT++))
  fi
done < <(env)

if [ "$INJECTED_COUNT" -gt 0 ]; then
  echo ""
  echo "Injected $INJECTED_COUNT environment variable(s)"
else
  echo ""
  echo "Warning: No REACT_APP_* or VITE_* variables found in environment"
  echo "Client will build without custom environment variables"
fi

#######################################
# BUILD CLIENT
#######################################
echo ""
echo "=== Running Client Build ==="

cd "$CLIENT_DIR"

# Check if build script exists
if ! npm run --silent 2>/dev/null | grep -q "build"; then
  echo "ERROR: No 'build' script found in client/package.json"
  exit 1
fi

npm run build

# Verify build output
if [ -d "build" ]; then
  echo ""
  echo "Client build completed successfully (output: ${CLIENT_DIR}/build/)"
  echo "Build contents:"
  ls -la build/ | head -10
elif [ -d "dist" ]; then
  echo ""
  echo "Client build completed successfully (output: ${CLIENT_DIR}/dist/)"
  echo "Build contents:"
  ls -la dist/ | head -10
else
  echo ""
  echo "Warning: Expected build output directory not found (build/ or dist/)"
  echo "Contents of ${CLIENT_DIR}:"
  ls -la
fi

cd ..

echo ""
echo "=== Client Build Complete ==="
