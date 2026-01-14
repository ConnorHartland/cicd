# EC2 Node Service Pipeline Template

Bitbucket Pipeline template for Node.js applications deploying to EC2 via S3 artifact upload and ASG instance refresh.

## Branch Strategy (PR-Driven Deployments)

### Feature Development
| Trigger | Stage | ENV_SUFFIX | Mode |
|---------|-------|------------|------|
| `feature/*` push | Build & Test | - | Auto |
| `feature/*` push | Deploy to Develop | `dev` | Manual |

### Release Process (PR from release/*)
| Trigger | Stage | ENV_SUFFIX | Mode |
|---------|-------|------------|------|
| PR from `release/*` | Build & Test + Release Report | - | Auto |
| PR from `release/*` | Deploy to Test | `test` | Auto |
| PR from `release/*` | Deploy to Staging | `qa` | Manual |
| PR from `release/*` | Deploy to Production | `prod` | Manual |

### Hotfix Process (PR from hotfix/* + custom pipeline)
| Trigger | Stage | ENV_SUFFIX | Mode |
|---------|-------|------------|------|
| PR from `hotfix/*` | Build & Test | - | Auto |
| `deploy-hotfix` pipeline | Build & Deploy to Prod | `prod` | Manual |

Hotfix PRs only run basic CI. Use `deploy-hotfix` custom pipeline for prod deployment.

### Post-Merge
| Trigger | Action |
|---------|--------|
| Merge to `main` | Create version tag (v2.11.0) |

## Setup

### 1. Copy Template Files

Copy the following to your service repository:
- `bitbucket-pipelines.yml` → root of your repo
- `scripts/` → root of your repo

### 2. Configure Repository Variables

Set these in Bitbucket Repository Settings → Repository variables:

**AWS Credentials (per environment):**
- `AWS_ACCESS_KEY_ID_DEV` / `AWS_SECRET_ACCESS_KEY_DEV`
- `AWS_ACCESS_KEY_ID_TEST` / `AWS_SECRET_ACCESS_KEY_TEST`
- `AWS_ACCESS_KEY_ID_QA` / `AWS_SECRET_ACCESS_KEY_QA`
- `AWS_ACCESS_KEY_ID_PROD` / `AWS_SECRET_ACCESS_KEY_PROD`

**SonarQube:**
- `SONAR_TOKEN`
- `SONAR_HOST_URL`

### 3. Configure Deployment Environments

In Bitbucket Repository Settings → Deployments, create environments with these variables:

**Develop:**
- `ENV_SUFFIX`: `dev`
- `AWS_SUFFIX`: `DEV`
- `S3_BUCKET`: `<your-app>-deploy-dev`
- `ASG_NAME`: `<your-app>-dev-asg`
- `SERVICE_NAME`: `<your-service-name>`
- `INSTANCE_WARMUP`: `180` (optional, default: 300)

**Test:**
- `ENV_SUFFIX`: `test`
- `AWS_SUFFIX`: `TEST`
- `S3_BUCKET`: `<your-app>-deploy-test`
- `ASG_NAME`: `<your-app>-test-asg`
- `SERVICE_NAME`: `<your-service-name>`
- `INSTANCE_WARMUP`: `180` (optional, default: 300)

**Staging:**
- `ENV_SUFFIX`: `qa`
- `AWS_SUFFIX`: `QA`
- `S3_BUCKET`: `<your-app>-deploy-qa`
- `ASG_NAME`: `<your-app>-qa-asg`
- `SERVICE_NAME`: `<your-service-name>`
- `INSTANCE_WARMUP`: `300` (optional, default: 300)

**Production:**
- `ENV_SUFFIX`: `prod`
- `AWS_SUFFIX`: `PROD`
- `S3_BUCKET`: `<your-app>-deploy-prod`
- `ASG_NAME`: `<your-app>-prod-asg`
- `SERVICE_NAME`: `<your-service-name>`
- `INSTANCE_WARMUP`: `300` (optional, default: 300)

### 4. Customize Scripts

**prisma_migration.sh:**
Edit the script to add your service's database configurations for each environment.

**setup_kafka.sh:**
Ensure your service has a `kafka:setup` npm script that reads from `kafka.yml`.

**SonarQube:**
SonarQube analysis runs inline in the pipeline. Ensure your repo has a `sonar-project.properties` file with `sonar.projectKey` configured.

## Usage

### Feature Development
1. Create `feature/my-feature` branch
2. CI automatically runs on push (lint, test, build, sonar)
3. Manually trigger "Deploy to Develop" when ready to test

### Release Process (PR from release/*)
1. Create `release/2.11.0` branch from your development branch
2. Open a **Pull Request** from `release/2.11.0` → `main`
3. PR pipeline automatically:
   - Runs CI (lint, test, build, sonar)
   - Posts release security report to PR comment
   - Deploys to Test environment
4. Review the release report in the PR
5. Manually trigger "Deploy to Staging" from the PR pipeline
6. Verify staging, then manually trigger "Deploy to Production"
7. After production is verified, **merge the PR**
8. Merging automatically creates `v2.11.0` tag on main

**Note:** Only PRs from `release/*` branches trigger the full deployment pipeline. Other PRs only run basic CI.

### Hotfix Process (Urgent Fixes)
1. Create `hotfix/fix-critical-bug` branch from `main`
2. Open a **Pull Request** from `hotfix/fix-critical-bug` → `main` (runs basic CI only)
3. Run the **deploy-hotfix** custom pipeline to build and deploy directly to production
4. After production is verified, **merge the PR**
5. Merging automatically creates version tag on main

### Custom Pipelines
- **deploy-to-develop**: Manual deploy to dev (with seed option)
- **deploy-to-test**: Manual deploy to test (with seed option)
- **deploy-hotfix**: Build + deploy directly to prod (emergency only)
- **setup-kafka**: Setup Kafka topics for an environment

**Note:** Staging and production deployments must go through the PR release cycle.

## Required npm Scripts

Your `package.json` should include:
```json
{
  "scripts": {
    "lint": "...",
    "test": "...",
    "build": "...",
    "kafka:setup": "...",
    "prisma:migration:deploy": "prisma migrate deploy",
    "prisma:generate": "prisma generate",
    "prisma:seed": "...",
    "prepare:test": "..."
  }
}
```

## Security Reports

### PR Report (All PRs)
For all PRs, the pipeline posts a condensed security report showing **issues introduced by this PR**:
- **SonarQube**: New bugs, vulnerabilities, code smells introduced in this PR
- **npm audit**: Dependency vulnerability counts by severity
- **Snyk**: Security scan results (if SNYK_TOKEN is configured)

### Release Report (Release PRs)
For PRs from `release/*` branches, a full consolidated report shows **project snapshot**:
- **SonarQube**: Total quality gate status, bugs, vulnerabilities, code smells, coverage
- **npm audit**: Full dependency vulnerability breakdown
- **Snyk**: Complete security scan results

The release report is:
1. Posted as a comment to the PR
2. Saved as `release-report.json` artifact
3. Printed to the pipeline console

### Additional Environment Variables for Reports
- `SNYK_TOKEN` - Snyk authentication (optional)
- `BITBUCKET_EMAIL` - For PR commenting
- `BITBUCKET_API_TOKEN` - For PR commenting

### Deployment Verification Variables (Optional)
Configure these per environment to enable post-deploy verification:

| Variable | Description | Default |
|----------|-------------|---------|
| `HEALTH_ENDPOINT` | HTTP health check URL (optional, only for HTTP services) | - |
| `SMOKE_TEST_REPO` | Bitbucket repo slug for smoke tests | - |
| `SMOKE_TEST_WORKSPACE` | Bitbucket workspace for smoke test repo | - |
| `ASG_REFRESH_TIMEOUT` | Max wait time for ASG refresh (seconds) | 600 |
| `HEALTH_CHECK_RETRIES` | Number of health check attempts | 10 |
| `HEALTH_CHECK_INTERVAL` | Seconds between health check retries | 10 |
| `SMOKE_TEST_TIMEOUT` | Max wait time for smoke tests (seconds) | 600 |

**Note:** Most services communicate via Kafka and don't have HTTP endpoints. Only configure `HEALTH_ENDPOINT` for services with health check routes.

## Deployment Verification

After each deployment, the pipeline runs a verification step that:

1. **Waits for ASG Refresh** - Polls AWS until the instance refresh completes (success/failure)
2. **Health Check** (optional) - If `HEALTH_ENDPOINT` is configured, verifies the service responds with HTTP 200
3. **Smoke Tests** (optional) - If `SMOKE_TEST_REPO` is configured, triggers a pipeline in the test repo and waits for completion

The pipeline fails if any verification step fails, providing immediate feedback on deployment issues.

## Self-Hosted Runner Requirements

- Node.js 22
- AWS CLI
- Prisma engines at `~/engines/`
- Kerberos tools (`kinit`, `kdestroy`)
- sonar-scanner (via npx)
- snyk CLI (optional, for security scanning)
- jq (for JSON processing)
