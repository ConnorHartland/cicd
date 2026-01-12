#!/bin/bash
set -e

echo "=== BeforeInstall: Stopping application ==="

# Stop the application gracefully
if command -v pm2 &> /dev/null; then
  pm2 stop all || true
  echo "PM2 processes stopped"
else
  echo "PM2 not found, skipping stop"
fi

# Clean up old deployment if exists
APP_DIR="/var/www/app"
if [ -d "$APP_DIR/dist" ]; then
  echo "Removing old dist folder"
  rm -rf "$APP_DIR/dist"
fi

echo "=== BeforeInstall complete ==="
