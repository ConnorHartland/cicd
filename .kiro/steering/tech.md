# Technology Stack

## Build System

- **CI/CD**: Bitbucket Pipelines with self-hosted runners
- **Deployment**: AWS S3 artifact upload + Auto Scaling Group instance refresh
- **Container Support**: Optional Docker builds to Docker Hub

## Tech Stack

### Runtime & Languages
- Node.js 22
- TypeScript
- React (for fullstack template)

### Infrastructure
- AWS S3 (artifact storage)
- AWS EC2 Auto Scaling Groups
- AWS CLI for deployments

### Code Quality & Security
- SonarQube (static analysis)
- npm audit (dependency scanning)
- Snyk (optional security scanning)
- ESLint (linting)
- Jest (testing with coverage)

### Database & Messaging
- Prisma ORM (with Kerberos authentication)
- Kafka (topic provisioning)

### Notifications
- Microsoft Teams (via Power Automate webhooks)
- New Relic (deployment markers)

## Common Commands

### Pipeline Scripts
```bash
# Database migrations
./scripts/prisma_migration.sh <service> <env> [seed]

# Kafka topic setup
./scripts/setup_kafka.sh <env> [allow_recreate]

# Build React client with env injection
./scripts/build_client.sh

# Teams notifications
./scripts/teams_notify.sh [start|success|failure]

# Deployment verification
./scripts/verify_deploy.sh

# Security reports
./scripts/pr_report.sh          # PR summary
./scripts/release_report.sh     # Full release report
```

### Required npm Scripts
Services using these templates must implement:
```json
{
  "scripts": {
    "lint": "eslint src/",
    "test": "jest --coverage",
    "build": "tsc",
    "kafka:setup": "...",
    "prisma:migration:deploy": "prisma migrate deploy",
    "prisma:generate": "prisma generate",
    "prisma:seed": "...",
    "prepare:test": "..."
  }
}
```

## Self-Hosted Runner Requirements

- Node.js 22
- AWS CLI
- Prisma engines at `~/engines/`
- Kerberos tools (`kinit`, `kdestroy`)
- sonar-scanner (global)
- snyk CLI (optional)
- jq (JSON processing)
- Docker (for docker-build pipeline)
