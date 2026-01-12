#!/bin/bash
set -e

echo "=== ApplicationStart: Starting application ==="

APP_DIR="/var/www/app"
cd "$APP_DIR"

# Start with PM2 as ec2-user
sudo -u ec2-user bash << 'EOF'
cd /var/www/app

# Check if ecosystem.config.js exists, otherwise use default
if [ -f "ecosystem.config.js" ]; then
  echo "Starting with ecosystem.config.js"
  pm2 start ecosystem.config.js
else
  echo "Starting with default config"
  pm2 start dist/index.js --name app
fi

# Save PM2 process list for restart on reboot
pm2 save
EOF

echo "=== ApplicationStart complete ==="
