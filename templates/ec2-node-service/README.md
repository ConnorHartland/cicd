# EC2 Node Service Pipeline Template

Bitbucket Pipeline template for Node.js applications deploying to EC2 via S3 artifact upload and ASG instance refresh.

## Branch Strategy (PR-Driven Deployments)

### Feature Development
| Trigger | Stage | ENV_SUFFIX | Mode |
|---------|-------|------------|------|
| `feature/*` push | Build & Test | - | Auto |
| `feature/*` push | Deploy to Develop | `dev` | Manual |

### Release Process (via PR to main)
| Trigger | Stage | ENV_SUFFIX | Mode |
|---------|-------|------------|------|
| PR to `main` | Build & Test + Release Report | - | Auto |
| PR to `main` | Deploy to Test | `test` | Auto |
| PR to `main` | Deploy to Staging | `qa` | Manual |
| PR to `main` | Deploy to Production | `prod` | Manual |

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

**Test:**
- `ENV_SUFFIX`: `test`
- `AWS_SUFFIX`: `TEST`
- `S3_BUCKET`: `<your-app>-deploy-test`
- `ASG_NAME`: `<your-app>-test-asg`
- `SERVICE_NAME`: `<your-service-name>`

**Staging:**
- `ENV_SUFFIX`: `qa`
- `AWS_SUFFIX`: `QA`
- `S3_BUCKET`: `<your-app>-deploy-qa`
- `ASG_NAME`: `<your-app>-qa-asg`
- `SERVICE_NAME`: `<your-service-name>`

**Production:**
- `ENV_SUFFIX`: `prod`
- `AWS_SUFFIX`: `PROD`
- `S3_BUCKET`: `<your-app>-deploy-prod`
- `ASG_NAME`: `<your-app>-prod-asg`
- `SERVICE_NAME`: `<your-service-name>`

### 4. Customize Scripts

**prisma_migration.sh:**
Edit the script to add your service's database configurations for each environment.

**setup_kafka.sh:**
Ensure your service has a `kafka:setup` npm script that reads from `kafka.yml`.

**sonar.sh:**
The script reads project info from `package.json`. Ensure your package has a `name` field.

## Usage

### Feature Development
1. Create `feature/my-feature` branch
2. CI automatically runs on push (lint, test, build, sonar)
3. Manually trigger "Deploy to Develop" when ready to test

### Release Process (PR-Driven)
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

### Custom Pipelines
- **deploy-to-develop**: Manual deploy to dev (with seed option)
- **deploy-to-test**: Manual deploy to test (with seed option)
- **deploy-to-staging**: Manual deploy to staging/qa
- **deploy-to-prod**: Manual deploy to production
- **setup-kafka**: Setup Kafka topics for an environment

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

## Release Security Report

For **PRs to main**, the pipeline automatically generates a consolidated security report that includes:
- **SonarQube**: Quality gate status, bugs, vulnerabilities, code smells, coverage
- **npm audit**: Dependency vulnerability counts by severity
- **Snyk**: Security scan results (if SNYK_TOKEN is configured)

The report is:
1. Posted as a comment to the PR (if in PR context)
2. Saved as `release-report.json` artifact
3. Printed to the pipeline console

### Additional Environment Variables for Reports
- `SNYK_TOKEN` - Snyk authentication (optional)
- `BITBUCKET_EMAIL` - For PR commenting
- `BITBUCKET_API_TOKEN` - For PR commenting

## Self-Hosted Runner Requirements

- Node.js 22
- AWS CLI
- Prisma engines at `~/engines/`
- Kerberos tools (`kinit`, `kdestroy`)
- sonar-scanner (global or via npm)
- snyk CLI (optional, for security scanning)
- jq (for JSON processing)
