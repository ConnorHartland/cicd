# AWS CodeBuild Setup Guide

This guide explains how to use the buildspec.yml templates with AWS CodeBuild and CodePipeline.

## Overview

The buildspec templates mirror the Bitbucket Pipeline functionality but are designed for AWS CodeBuild. They support:
- Multi-environment deployments (dev, test, staging, production)
- Security scanning (SonarQube, npm audit, Snyk)
- Deployment verification with ASG health monitoring
- Microsoft Teams notifications
- Database migrations (Prisma)
- Kafka topic provisioning

## Prerequisites

### AWS Systems Manager Parameter Store
Store these parameters in Parameter Store (SecureString type):
```
/codebuild/sonar/token
/codebuild/sonar/host
/codebuild/newrelic/api-key
/codebuild/teams/webhook
```

### AWS Secrets Manager
Store deployment credentials in Secrets Manager:
```json
{
  "name": "codebuild/aws-deploy",
  "secret": {
    "access_key_id": "AKIA...",
    "secret_access_key": "..."
  }
}
```

### IAM Role Permissions
The CodeBuild service role needs:
- S3 read/write access to artifact buckets
- Auto Scaling Group refresh permissions
- Parameter Store read access
- Secrets Manager read access
- CloudWatch Logs write access

## CodeBuild Project Setup

### 1. Create CodeBuild Project

```bash
aws codebuild create-project \
  --name my-service-build \
  --source type=GITHUB,location=https://github.com/org/repo.git \
  --artifacts type=S3,location=my-artifacts-bucket \
  --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:7.0,computeType=BUILD_GENERAL1_MEDIUM \
  --service-role arn:aws:iam::ACCOUNT:role/CodeBuildServiceRole
```

### 2. Environment Variables

Set these in the CodeBuild project or CodePipeline stage:

#### For CI Only (no deployment)
```
DEPLOY_ENABLED=false
```

#### For Deployment Builds
```
DEPLOY_ENABLED=true
ENVIRONMENT=dev|test|staging|prod
ENV_SUFFIX=dev|test|qa|prod
SERVICE_NAME=my-service
S3_BUCKET=my-service-artifacts-dev
ASG_NAME=my-service-asg-dev
INSTANCE_WARMUP=300
```

#### Optional Variables
```
SEED=true|false                    # Run database seeds (non-prod only)
ALLOW_TOPIC_RECREATE=true|false    # Allow Kafka topic recreation (non-prod only)
```

## CodePipeline Integration

### Example Pipeline Structure

```yaml
# CloudFormation template for CodePipeline
Resources:
  Pipeline:
    Type: AWS::CodePipeline::Pipeline
    Properties:
      Stages:
        # Source stage
        - Name: Source
          Actions:
            - Name: SourceAction
              ActionTypeId:
                Category: Source
                Owner: AWS
                Provider: GitHub
                Version: 1
              Configuration:
                Owner: my-org
                Repo: my-repo
                Branch: main
                OAuthToken: !Ref GitHubToken
              OutputArtifacts:
                - Name: SourceOutput

        # Build & Test (CI)
        - Name: Build
          Actions:
            - Name: BuildAction
              ActionTypeId:
                Category: Build
                Owner: AWS
                Provider: CodeBuild
                Version: 1
              Configuration:
                ProjectName: !Ref CIBuildProject
                EnvironmentVariables: |
                  [
                    {"name":"DEPLOY_ENABLED","value":"false","type":"PLAINTEXT"}
                  ]
              InputArtifacts:
                - Name: SourceOutput
              OutputArtifacts:
                - Name: BuildOutput

        # Deploy to Test
        - Name: DeployTest
          Actions:
            - Name: DeployAction
              ActionTypeId:
                Category: Build
                Owner: AWS
                Provider: CodeBuild
                Version: 1
              Configuration:
                ProjectName: !Ref DeployBuildProject
                EnvironmentVariables: |
                  [
                    {"name":"DEPLOY_ENABLED","value":"true","type":"PLAINTEXT"},
                    {"name":"ENVIRONMENT","value":"test","type":"PLAINTEXT"},
                    {"name":"ENV_SUFFIX","value":"test","type":"PLAINTEXT"},
                    {"name":"SERVICE_NAME","value":"my-service","type":"PLAINTEXT"},
                    {"name":"S3_BUCKET","value":"my-service-artifacts-test","type":"PLAINTEXT"},
                    {"name":"ASG_NAME","value":"my-service-asg-test","type":"PLAINTEXT"}
                  ]
              InputArtifacts:
                - Name: SourceOutput

        # Deploy to Production (with manual approval)
        - Name: DeployProduction
          Actions:
            - Name: ApprovalAction
              ActionTypeId:
                Category: Approval
                Owner: AWS
                Provider: Manual
                Version: 1
            - Name: DeployAction
              ActionTypeId:
                Category: Build
                Owner: AWS
                Provider: CodeBuild
                Version: 1
              Configuration:
                ProjectName: !Ref DeployBuildProject
                EnvironmentVariables: |
                  [
                    {"name":"DEPLOY_ENABLED","value":"true","type":"PLAINTEXT"},
                    {"name":"ENVIRONMENT","value":"prod","type":"PLAINTEXT"},
                    {"name":"ENV_SUFFIX","value":"prod","type":"PLAINTEXT"},
                    {"name":"SERVICE_NAME","value":"my-service","type":"PLAINTEXT"},
                    {"name":"S3_BUCKET","value":"my-service-artifacts-prod","type":"PLAINTEXT"},
                    {"name":"ASG_NAME","value":"my-service-asg-prod","type":"PLAINTEXT"}
                  ]
              InputArtifacts:
                - Name: SourceOutput
              RunOrder: 2
```

## Build Types

The buildspec automatically detects the build context:

### PR Builds
- Triggered by pull request webhooks
- Runs `pr_report.sh` for condensed security report
- No deployment

### Release Builds
- Triggered by branches matching `release/*`
- Runs `release_report.sh` for full security report
- Includes version in SonarQube analysis
- Can deploy through pipeline stages

### Standard Builds
- All other branches
- Basic CI only

## Deployment Flow

When `DEPLOY_ENABLED=true`:

1. **Pre-deployment**
   - Setup Kafka topics
   - Run Prisma migrations

2. **Deploy**
   - Send Teams notification (start)
   - Upload artifact to S3
   - Trigger ASG instance refresh

3. **Verify**
   - Monitor ASG refresh status
   - Run smoke tests
   - Send Teams notification (success/failure)
   - Create New Relic deployment marker

## Differences from Bitbucket Pipelines

### What's the Same
- Build steps and script logic
- Security scanning workflow
- Deployment verification process
- Notification integrations

### What's Different
- **No custom pipelines**: Use separate CodeBuild projects or pipeline stages
- **No manual triggers**: Use CodePipeline manual approval actions
- **Environment variables**: Set via CodeBuild project or pipeline stage config
- **Artifacts**: Stored in S3 instead of Bitbucket artifacts
- **Caching**: Uses CodeBuild cache instead of pipeline cache

## Migration Checklist

- [ ] Create Parameter Store entries for secrets
- [ ] Create Secrets Manager entry for AWS deploy credentials
- [ ] Set up IAM role with required permissions
- [ ] Create CodeBuild project(s)
- [ ] Configure environment variables
- [ ] Copy scripts folder to repository
- [ ] Test CI build (DEPLOY_ENABLED=false)
- [ ] Test deployment to dev environment
- [ ] Set up CodePipeline with approval gates
- [ ] Configure webhook triggers (if using GitHub/Bitbucket source)

## Troubleshooting

### Build fails at npm ci
- Check Node.js version in buildspec matches your package.json engines
- Verify package-lock.json is committed

### SonarQube analysis fails
- Verify Parameter Store values are set correctly
- Check sonar-project.properties exists in repository

### Deployment fails at S3 upload
- Verify IAM role has S3 permissions
- Check S3 bucket name is correct

### ASG refresh doesn't start
- Verify IAM role has autoscaling:StartInstanceRefresh permission
- Check ASG name is correct for the environment

### Scripts not found
- Ensure scripts folder is copied to repository root
- Verify scripts have execute permissions (git update-index --chmod=+x scripts/*.sh)
