# Deployment Pipeline Improvements

## Summary

This PR introduces several improvements to the deployment pipeline, including enhanced Teams notifications, flexible deployment methods, and a streamlined pipeline structure.

---

## Changes

### 1. Teams Adaptive Card Redesign

**File:** `adaptive-card.json`

- Added colored header container based on deployment status (green/yellow/blue)
- Status icons: 🚀 (start), ✅ (success), ❌ (failure)
- Reorganized layout with separate sections for deployment info and metadata
- Commit message displayed as standalone italic text
- Combined "triggered by" with trigger type (e.g., "John Smith (manual)")
- Simplified to single "View Pipeline" action button

### 2. Teams Notification Script Updates

**File:** `scripts/teams_notify.sh`

- Added status icons to payload
- Combined `triggeredBy` and `triggerType` into single `triggeredByFull` field
- Fixed Bitbucket API authentication (using `BITBUCKET_EMAIL` and `BITBUCKET_API_TOKEN`)
- Fixed pipeline API endpoint to use build number instead of UUID
- Duration now calculated from `created_on`/`completed_on` timestamps (works with self-hosted runners)

### 3. New ASG Deployment Script

**File:** `scripts/deploy_asg.sh`

Supports two deployment methods:

| Method | Command | Description |
|--------|---------|-------------|
| `refresh` | `./deploy_asg.sh refresh` | Rolling instance refresh via ASG (default, fire-and-forget) |
| `ssm` | `./deploy_asg.sh ssm` | Direct push to instances via SSM (waits for completion) |

**Environment variables:**
- `ASG_NAME` - Auto Scaling Group name (required)
- `S3_BUCKET` - S3 bucket for artifacts (required)
- `DEPLOY_METHOD` - `refresh` or `ssm` (default: refresh)
- `INSTANCE_WARMUP` - Seconds for warmup (default: 300)
- `WEBAPP_SERVICE` - Systemd service name (default: webapp)
- `WEBAPP_DIR` - Install directory (default: /opt/webapp)

### 4. Updated Verify Deploy Script

**File:** `scripts/verify_deploy.sh`

- Skips ASG refresh wait when using SSM deploy (already completed synchronously)
- Continues to wait for instance refresh when using refresh method
- Smoke tests still run for both methods (if configured)

### 5. Simplified Pipeline Structure

**File:** `bitbucket-pipelines.yml`

- Merged deploy and verify into single step
- Added `after-script` for Teams notifications (always runs, even on failure)
- Teams notification now reflects actual deployment outcome via `$BITBUCKET_EXIT_CODE`
- Removed separate `verify-deploy` step from all stages

**New deploy step flow:**
```
script:
  1. teams_notify.sh start
  2. Upload build to S3
  3. deploy_asg.sh (refresh or ssm)
  4. verify_deploy.sh (wait + smoke tests)
  5. newrelic_deploy.sh

after-script:
  - teams_notify.sh success/failure (always runs)
```

---

## Usage

### Default (Instance Refresh)
No changes needed - works as before with rolling instance refresh.

### SSM Deploy
Set `DEPLOY_METHOD=ssm` in your deployment environment variables to push directly to running instances without waiting for ASG refresh.

---

## Testing

1. Trigger a deployment and verify Teams notification appears with new card design
2. Verify duration shows on success/failure notifications
3. Test SSM deploy method by setting `DEPLOY_METHOD=ssm`
4. Verify failure notifications are sent when deployment fails
