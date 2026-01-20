# Product Overview

This repository contains enterprise CI/CD pipeline templates for Node.js microservices deploying to AWS EC2 via Auto Scaling Groups.

## Purpose

Provides reusable Bitbucket Pipeline configurations and deployment scripts for:
- **EC2 Node Service**: Backend-only Node.js/TypeScript services
- **EC2 Node Fullstack**: Monorepo projects with Node.js server + React client

## Key Features

- Multi-environment deployments (dev, test, staging, production)
- PR-driven release workflow with approval gates
- Automated security scanning (SonarQube, npm audit, Snyk)
- Deployment verification with ASG health monitoring
- Microsoft Teams notifications
- Database migrations (Prisma with Kerberos auth)
- Kafka topic provisioning

## Target Users

DevOps teams and development teams deploying Node.js services to AWS EC2 infrastructure.
