# EC2 Node Fullstack Pipeline Template

CI/CD pipeline template for monorepo projects with:
- **Server**: Node.js/Express at repository root
- **Client**: React app in `client/` directory
- Server serves the client build as static files

## Project Structure Expected

```
your-repo/
├── package.json           # Server dependencies
├── src/                   # Server source code
├── dist/                  # Server build output
├── client/
│   ├── package.json       # Client dependencies
│   ├── src/               # React source code
│   └── build/             # Client build output (or dist/ for Vite)
├── scripts/               # Pipeline scripts (copy from this template)
├── bitbucket-pipelines.yml
└── sonar-project.properties
```

## Quick Setup

1. Copy files to your repo:
   ```bash
   cp bitbucket-pipelines.yml /path/to/your-repo/
   cp sonar-project.properties /path/to/your-repo/
   cp -r scripts/ /path/to/your-repo/scripts/
   chmod +x /path/to/your-repo/scripts/*.sh
   ```

2. Update `sonar-project.properties`:
   - Set `sonar.projectKey` to your project key
   - Set `sonar.projectName` to your project name

3. Configure Bitbucket Repository Variables (Settings > Repository variables)

## Required Variables

### AWS Deployment
| Variable | Description |
|----------|-------------|
| `AWS_ACCESS_KEY_ID_DEV` | AWS access key for dev environment |
| `AWS_SECRET_ACCESS_KEY_DEV` | AWS secret key for dev environment |
| `AWS_ACCESS_KEY_ID_TEST` | AWS access key for test environment |
| `AWS_SECRET_ACCESS_KEY_TEST` | AWS secret key for test environment |
| `AWS_ACCESS_KEY_ID_QA` | AWS access key for QA environment |
| `AWS_SECRET_ACCESS_KEY_QA` | AWS secret key for QA environment |
| `AWS_ACCESS_KEY_ID_PROD` | AWS access key for production |
| `AWS_SECRET_ACCESS_KEY_PROD` | AWS secret key for production |

### Bitbucket API (for PR comments)
| Variable | Description |
|----------|-------------|
| `BITBUCKET_EMAIL` | Email for Bitbucket API auth |
| `BITBUCKET_API_TOKEN` | App password with PR write access |

### Code Quality
| Variable | Description |
|----------|-------------|
| `SONAR_HOST_URL` | SonarQube server URL |
| `SONAR_TOKEN` | SonarQube authentication token |

### Client Environment Variables
| Variable | Description |
|----------|-------------|
| `REACT_APP_*` | Any `REACT_APP_` prefixed variable will be injected into client/.env at build time |
| `VITE_*` | Any `VITE_` prefixed variable will be injected (for Vite-based apps) |

Example client variables:
- `REACT_APP_API_URL` - Backend API endpoint
- `REACT_APP_ENV` - Environment name
- `REACT_APP_FEATURE_FLAG` - Feature flags

## Optional Variables

### Security Scanning
| Variable | Description |
|----------|-------------|
| `SNYK_TOKEN` | Snyk API token for vulnerability scanning |

### Notifications
| Variable | Description |
|----------|-------------|
| `TEAMS_WEBHOOK_URL` | Microsoft Teams webhook for deployment notifications |
| `NEW_RELIC_API_KEY` | New Relic API key for deployment markers |
| `NEW_RELIC_ENTITY_GUID` | New Relic entity GUID |

### Smoke Tests
| Variable | Description |
|----------|-------------|
| `SMOKE_TEST_WORKSPACE` | Bitbucket workspace containing smoke test repo |
| `SMOKE_TEST_REPO` | Repository name for smoke tests |

## Deployment Variables (per environment)

Configure these in Bitbucket Deployments settings:

| Variable | Description |
|----------|-------------|
| `ENV_SUFFIX` | Environment name: `dev`, `test`, `qa`, `prod` |
| `AWS_SUFFIX` | AWS variable suffix: `DEV`, `TEST`, `QA`, `PROD` |
| `S3_BUCKET` | S3 bucket for deployment artifacts |
| `ASG_NAME` | Auto Scaling Group name |
| `SERVICE_NAME` | Service identifier |
| `INSTANCE_WARMUP` | ASG instance warmup time (default: 300) |

## Pipeline Flow

### Feature Branches (`feature/*`)
```
Push → Build & Test (server + client) → [Manual] Deploy to Dev
```

### Release Branches (`release/*`)
```
PR Created → Build & Test → Release Report
          → [Auto] Deploy to Test
          → [Manual] Deploy to Staging
          → [Manual] Deploy to Production

Merge to main → Auto-tag (v1.0.0)
```

## Build Process

The pipeline:
1. Installs server dependencies (`npm ci` at root)
2. Installs client dependencies (`npm ci` in client/)
3. Runs server lint and tests
4. Runs client lint and tests
5. Builds server (`npm run build`)
6. Injects env vars and builds client (`scripts/build_client.sh`)
7. Runs SonarQube analysis (both codebases)
8. Generates security report (npm audit + Snyk for both)
9. Packages artifact: `dist/`, `node_modules/`, `client/build/`

## Security Reports

Reports scan **both** server and client dependencies:
- **npm audit**: Combined vulnerability count from root + client
- **Snyk**: Combined scan results (if SNYK_TOKEN configured)
- **SonarQube**: Single analysis covering both codebases

Reports are posted to PR comments and saved as `release-report.json` artifact.

## Customization

### Different client directory
If your client is not in `client/`, update:
- `bitbucket-pipelines.yml` - change `cd client` references
- `scripts/build_client.sh` - set `CLIENT_DIR` variable
- `scripts/report_utils.sh` - update client path in scan functions
- `sonar-project.properties` - update `sonar.sources`

### Vite instead of Create React App
The template supports both. Vite apps use `VITE_*` env vars instead of `REACT_APP_*`.
The build script automatically detects `dist/` vs `build/` output directories.
