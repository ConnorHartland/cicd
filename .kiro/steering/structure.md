# Project Structure

## Repository Organization

```
.
├── templates/                    # Pipeline templates for different project types
│   ├── ec2-node-service/        # Backend-only Node.js services
│   │   ├── bitbucket-pipelines.yml
│   │   ├── README.md            # Quick reference
│   │   ├── DOCUMENTATION.md     # Full setup guide
│   │   └── scripts/             # Deployment and utility scripts
│   │       ├── prisma_migration.sh
│   │       ├── setup_kafka.sh
│   │       ├── verify_deploy.sh
│   │       ├── teams_notify.sh
│   │       ├── pr_report.sh
│   │       ├── release_report.sh
│   │       ├── report_utils.sh
│   │       └── newrelic_deploy.sh
│   │
│   └── ec2-node-fullstack/      # Monorepo with server + React client
│       ├── bitbucket-pipelines.yml
│       ├── README.md
│       ├── sonar-project.properties
│       └── scripts/
│           ├── build_client.sh  # React build with env injection
│           └── [same scripts as service template]
│
├── node-pipe/                   # Simplified pipeline variant
│   ├── bitbucket-pipelines.yml
│   └── scripts/
│
├── diagrams/                    # Architecture diagrams (draw.io)
│   ├── pipeline-flow.drawio
│   ├── integration-architecture.drawio
│   ├── deployment-verification.drawio
│   └── branch-strategy.drawio
│
├── adaptive-card.json           # Teams notification card template
└── RELEASE_NOTES.md            # Version history and features
```

## Template Types

### ec2-node-service
For backend-only Node.js/TypeScript services:
- Single build artifact (dist + node_modules)
- Prisma database migrations
- Kafka topic provisioning
- Standard deployment flow

### ec2-node-fullstack
For monorepo projects with server + client:
- Server at repository root
- React client in `client/` subdirectory
- Client built per-environment with env variable injection
- Combined SonarQube analysis
- Server serves client as static files

### node-pipe
Simplified variant with:
- Shared pipeline utilities at `~/pipeline-utils/`
- Streamlined configuration
- Fewer custom pipelines

## Script Categories

### Deployment Scripts
- `verify_deploy.sh`: ASG refresh monitoring + smoke tests
- `prisma_migration.sh`: Database migrations with Kerberos
- `setup_kafka.sh`: Kafka topic provisioning
- `build_client.sh`: React build with env injection (fullstack only)

### Notification Scripts
- `teams_notify.sh`: Microsoft Teams deployment notifications
- `newrelic_deploy.sh`: New Relic deployment markers

### Security & Reporting Scripts
- `pr_report.sh`: Condensed security report for PRs
- `release_report.sh`: Full security report for releases
- `report_utils.sh`: Shared reporting functions

## Branch Strategy

### Feature Development
- `feature/*` branches: CI only, manual deploy to dev

### Release Process
- `release/*` branches: Full pipeline via PR to main
  - Auto-deploy to test
  - Manual approval for staging
  - Manual approval for production
  - Auto-tag on merge (v1.0.0)

### Hotfix Process
- `hotfix/*` branches: CI only, use `deploy-hotfix` custom pipeline for prod

### Main Branch
- Merge destination for releases
- Auto-creates version tags
- No direct deployments

## Configuration Files

### Pipeline Configuration
- `bitbucket-pipelines.yml`: Main pipeline definition with stages and steps

### Code Quality
- `sonar-project.properties`: SonarQube analysis configuration

### Notifications
- `adaptive-card.json`: Teams notification card template for Power Automate

## Diagrams

All diagrams are draw.io format (`.drawio`) and can be:
- Imported to Confluence using draw.io macro
- Edited at diagrams.net
- Exported as PNG/SVG

Available diagrams:
- **pipeline-flow**: Release pipeline stages and triggers
- **integration-architecture**: System components and data flow
- **deployment-verification**: ASG refresh and smoke test flow
- **branch-strategy**: Git branching and environment mapping
