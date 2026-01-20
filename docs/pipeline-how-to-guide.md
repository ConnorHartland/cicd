# CI/CD Pipeline How-To Guide

A practical guide for developers and product owners on using the CI/CD pipelines.

---

## Table of Contents

1. [Pipeline Overview](#pipeline-overview)
2. [Branch Workflow](#branch-workflow)
3. [Creating a Release](#creating-a-release)
4. [Understanding Pipeline Stages](#understanding-pipeline-stages)
5. [Approving Deployments](#approving-deployments)
6. [Reading PR Reports](#reading-pr-reports)
7. [Reading Release Reports](#reading-release-reports)
8. [Teams Notifications](#teams-notifications)
9. [Deployment Verification](#deployment-verification)
10. [Troubleshooting](#troubleshooting)

---

## Pipeline Overview

The pipeline follows a **"Build Once, Deploy Multiple"** approach:

```
Feature Branch → Release Branch → Test → Staging → Production → Main (Tagged)
```

| Environment | Trigger | Approval Required |
|-------------|---------|-------------------|
| Test | Automatic on release/* branch | No |
| Staging | Manual | Yes - Admin only |
| Production | Manual | Yes - Admin only |

---

## Branch Workflow

### Feature Development

1. Create a feature branch from `main`:
   ```
   feature/JIRA-123-add-login
   ```

2. Push commits to trigger build & test pipeline

3. Create a Pull Request to a `release/*` branch

4. Pipeline runs automatically:
   - ✅ Build
   - ✅ Unit Tests
   - ✅ Security Scans (SonarQube, npm audit, Snyk)
   - ✅ PR Report posted as comment

### Release Branches

Release branches follow the naming convention:
```
release/2.11.0
release/2025-Q1
release/sprint-42
```

When code is pushed to a release branch:
1. Build & Test runs automatically
2. **Test environment** deploys automatically
3. **Staging** waits for manual approval
4. **Production** waits for manual approval

---

## Creating a Release

### Step 1: Create Release Branch

Create a release branch from `main`:
```bash
git checkout main
git pull
git checkout -b release/2.11.0
git push -u origin release/2.11.0
```

### Step 2: Merge Features

Merge approved feature PRs into the release branch.

### Step 3: Deploy Through Environments

1. **Test** - Deploys automatically when PR is merged
2. **Staging** - Click "Run" on the Staging stage (admin approval)
3. **Production** - Click "Run" on the Production stage (admin approval)

### Step 4: Merge to Main

After Production deployment is verified:
1. Create PR from `release/*` to `main`
2. Merge the PR
3. A version tag is automatically created (e.g., `v2.11.0`)

---

## Understanding Pipeline Stages

### What Happens at Each Stage

| Stage | What Runs | Duration |
|-------|-----------|----------|
| **Build** | npm install, TypeScript compile, build artifacts | 2-5 min |
| **Test** | Unit tests, linting | 1-3 min |
| **Security Scan** | SonarQube analysis, npm audit, Snyk scan | 2-4 min |
| **Deploy to Test** | Upload to S3, trigger ASG refresh, verify health | 3-8 min |
| **Deploy to Staging** | Same as Test (manual trigger) | 3-8 min |
| **Deploy to Production** | Same as Staging (manual trigger) | 3-8 min |

### Pipeline Status Icons

| Icon | Meaning |
|------|---------|
| 🔵 Running | Stage is currently executing |
| ✅ Passed | Stage completed successfully |
| ❌ Failed | Stage failed - check logs |
| ⏸️ Paused | Waiting for manual approval |
| ⏭️ Skipped | Stage was skipped |

---

## Approving Deployments

### Who Can Approve?

Only users with **Admin** access to the repository can approve Staging and Production deployments.

### How to Approve

1. Navigate to the pipeline in Bitbucket
2. Find the paused stage (Staging or Production)
3. Click the **"Run"** button on the stage
4. Confirm the deployment

### Before You Approve

Checklist before approving to Staging:
- [ ] PR Report shows no critical security issues
- [ ] Test environment deployment succeeded
- [ ] Basic smoke tests passed in Test

Checklist before approving to Production:
- [ ] Release Report shows PASSED status
- [ ] Staging deployment succeeded
- [ ] QA sign-off received
- [ ] Stakeholders notified

---

## Reading PR Reports

PR Reports are automatically posted as comments on Pull Requests.

### Report Sections

```
┌─────────────────────────────────────────────────┐
│ 🔒 Security Scan Summary                        │
├─────────────────────────────────────────────────┤
│ SonarQube Quality Gate: ✅ Passed               │
│                                                 │
│ npm audit:                                      │
│   Critical: 0  High: 0  Moderate: 2  Low: 5    │
│                                                 │
│ Snyk:                                           │
│   Critical: 0  High: 1  Moderate: 0  Low: 0    │
└─────────────────────────────────────────────────┘
```

### What to Look For

| Finding | Action Required |
|---------|-----------------|
| **Critical vulnerabilities** | Must fix before merge |
| **High vulnerabilities** | Review and fix if possible |
| **SonarQube Quality Gate Failed** | Fix blocking issues |
| **Moderate/Low issues** | Track for future remediation |

### Accessing Full Details

- Click the **SonarQube link** in the report for detailed code analysis
- Run `npm audit` locally to see full vulnerability details
- Check Snyk dashboard for dependency recommendations

---

## Reading Release Reports

Release Reports provide a comprehensive quality gate for releases.

### Report Structure

```
╔══════════════════════════════════════════════════════════╗
║  RELEASE REPORT                                          ║
║  my-service v2.11.0                                      ║
╠══════════════════════════════════════════════════════════╣
║  Overall Status: ✅ PASSED                               ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║  📊 SONARQUBE ANALYSIS                                   ║
║  ────────────────────                                    ║
║  Quality Gate: ✅ OK                                     ║
║  Bugs: 0  Vulnerabilities: 0  Code Smells: 12           ║
║  Coverage: 78.5%  Security Hotspots: 0                  ║
║                                                          ║
║  📦 NPM AUDIT                                            ║
║  ────────────────────                                    ║
║  Critical: 0  High: 0  Moderate: 2  Low: 5              ║
║                                                          ║
║  🔍 SNYK SCAN                                            ║
║  ────────────────────                                    ║
║  Critical: 0  High: 0  Moderate: 1  Low: 0              ║
║                                                          ║
║  📝 CHANGES IN THIS RELEASE                              ║
║  ────────────────────                                    ║
║  abc1234 - Add user authentication (jsmith)             ║
║  def5678 - Fix login timeout bug (mjones)               ║
║  ghi9012 - Update dependencies (jsmith)                 ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
```

### Status Meanings

| Status | Meaning | Action |
|--------|---------|--------|
| ✅ **PASSED** | All quality gates passed | Safe to deploy |
| ⚠️ **WARNINGS** | High-severity issues found | Review before deploying |
| ❌ **FAILED** | Critical issues found | Do not deploy - fix first |

### Quality Gate Criteria

The release **FAILS** if any of these are true:
- SonarQube Quality Gate = ERROR
- npm audit has Critical vulnerabilities
- Snyk has Critical vulnerabilities

The release shows **WARNINGS** if:
- npm audit has High vulnerabilities
- Snyk has High vulnerabilities

---

## Teams Notifications

Deployment notifications are sent to Microsoft Teams automatically.

### Notification Types

| Status | Message |
|--------|---------|
| 🚀 **Started** | "Deployment to [ENV] started" |
| ✅ **Succeeded** | "Deployment to [ENV] succeeded" |
| ❌ **Failed** | "Deployment to [ENV] failed" |

### Notification Content

Each notification includes:
- Service name
- Environment (DEV/TEST/STAGING/PROD)
- Branch name
- Commit SHA
- Timestamp
- Quick links to:
  - View Pipeline
  - View Commit
  - View Branch

### Setting Up Notifications

Teams notifications require a webhook URL configured in Bitbucket:

1. Create an Incoming Webhook in Teams (or Power Automate flow)
2. Add `TEAMS_WEBHOOK_URL` as a repository variable in Bitbucket
3. Notifications will begin automatically on next deployment

---

## Deployment Verification

After each deployment, the pipeline automatically verifies success.

### What Gets Verified

1. **Instance Health** - All instances in Auto Scaling Group are healthy
2. **Version Check** - New version is running on all instances
3. **Health Endpoint** - Application health endpoint returns OK

### Verification Timeout

The pipeline waits up to **5 minutes** for all instances to become healthy. If verification fails:
- Pipeline is marked as failed
- Teams notification sent with failure status
- Previous version continues running (no downtime)

### Smoke Tests (If Configured)

If smoke tests are configured, they run automatically after deployment verification:
- External test suite is triggered
- Pipeline waits up to 10 minutes for results
- Pipeline fails if smoke tests fail

---

## Troubleshooting

### Pipeline Failed at Build Stage

**Common causes:**
- TypeScript compilation errors
- Missing dependencies
- Invalid configuration

**Actions:**
1. Check the build logs for specific errors
2. Run `npm run build` locally to reproduce
3. Fix errors and push new commit

### Pipeline Failed at Test Stage

**Common causes:**
- Unit test failures
- Linting errors

**Actions:**
1. Check test output in pipeline logs
2. Run `npm test` locally
3. Fix failing tests and push

### Pipeline Failed at Security Scan

**Common causes:**
- SonarQube Quality Gate failed
- Critical vulnerabilities in dependencies

**Actions:**
1. Review the PR Report or Release Report
2. Click through to SonarQube for code issues
3. Run `npm audit fix` for dependency issues
4. Update or replace vulnerable packages

### Deployment Failed

**Common causes:**
- AWS credentials invalid or expired
- S3 bucket permissions
- Auto Scaling Group issues
- Health check failures

**Actions:**
1. Check deployment logs in pipeline
2. Verify AWS credentials are current
3. Check ASG instance status in AWS Console
4. Review application logs on EC2 instances

### Verification Failed

**Common causes:**
- Application crashed on startup
- Health endpoint not responding
- Configuration issues in environment

**Actions:**
1. SSH to an instance and check application logs
2. Verify environment variables are set correctly
3. Check if application starts locally with production config

### Not Receiving Teams Notifications

**Common causes:**
- `TEAMS_WEBHOOK_URL` not configured
- Webhook URL expired or invalid

**Actions:**
1. Verify `TEAMS_WEBHOOK_URL` exists in Bitbucket repository variables
2. Test the webhook URL manually
3. Regenerate webhook in Teams if needed

---

## Quick Reference

### Pipeline Commands (Custom Pipelines)

| Pipeline | When to Use |
|----------|-------------|
| `deploy-to-develop` | Deploy any branch to DEV environment |
| `deploy-to-test` | Deploy any branch to TEST environment |
| `deploy-hotfix` | Emergency production deployment |

### Key Contacts

| Role | Responsibility |
|------|----------------|
| DevOps Team | Pipeline issues, AWS access |
| Security Team | Vulnerability remediation guidance |
| QA Team | Staging sign-off |

### Useful Links

- [Bitbucket Pipelines](https://bitbucket.org) - View pipeline runs
- [SonarQube Dashboard](https://sonarqube.example.com) - Code quality details
- [AWS Console](https://aws.amazon.com) - Infrastructure status

---

## FAQ

**Q: Can I skip the Test environment and deploy directly to Staging?**
A: No. The pipeline enforces Test → Staging → Production order for release branches.

**Q: How do I deploy a hotfix to Production quickly?**
A: Use the `deploy-hotfix` custom pipeline. This still requires admin approval but skips lower environments.

**Q: What happens if I merge to main without deploying to Production?**
A: The version tag will be created, but the code won't be in Production. Always complete the full deployment flow before merging to main.

**Q: Can I re-run a failed deployment?**
A: Yes. Click "Rerun" on the failed stage in Bitbucket Pipelines. If the issue was transient (network, AWS hiccup), it may succeed on retry.

**Q: How do I know what version is deployed to each environment?**
A: Check the Teams channel for recent deployment notifications, or view the pipeline history in Bitbucket filtered by environment.
