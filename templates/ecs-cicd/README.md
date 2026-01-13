# ECS CI/CD Pipeline Templates

SOC2-compliant CI/CD pipeline using Bitbucket (CI) + AWS CodePipeline (CD) with ECS Fargate.

## Branching Strategy (GitFlow)

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                        main                              │
                    │                    (production)                          │
                    └──────────────────────────┬──────────────────────────────┘
                                               │
         ┌─────────────────────────────────────┼─────────────────────────────────────┐
         │                                     │                                     │
         │              hotfix/*               │                                     │
         │            (emergency)              │                                     │
         │                 │                   │                                     │
         │                 ▼                   │                                     │
         │           ┌───────────┐             │                                     │
         │           │  hotfix/  │─────────────┼──────────────────────────┐          │
         │           │  fix-bug  │             │                          │          │
         │           └───────────┘             │                          │          │
         │                                     │                          ▼          │
         │                                     │                    ┌──────────┐     │
         │                                     │                    │   PROD   │     │
         │                                     │                    │  Deploy  │     │
         │                                     │                    └──────────┘     │
         │                                     │                          ▲          │
         │                                     │                          │          │
         │                                     ▼                          │          │
         │    ┌────────────────────────────────────────────────────┐      │          │
         │    │                    release/*                        │      │          │
         │    │               (release candidate)                   │──────┘          │
         │    └────────────────────────┬───────────────────────────┘                  │
         │                             │                                              │
         │                             │  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
         │                             │  │   TEST   │  │ STAGING  │  │   PROD   │   │
         │                             └─>│  Deploy  │─>│  Deploy  │─>│  Deploy  │   │
         │                                └──────────┘  └──────────┘  └──────────┘   │
         │                                      ▲                                     │
         │                                      │                                     │
         │    ┌─────────────────────────────────┴──────────────────────────────┐     │
         │    │                       develop                                   │     │
         │    │                   (integration)                                 │     │
         │    └────────────────────────┬───────────────────────────────────────┘     │
         │                             │                                              │
         │                             │  ┌──────────┐                                │
         │                             └─>│   DEV    │                                │
         │                                │  Deploy  │                                │
         │                                └──────────┘                                │
         │                                      ▲                                     │
         │                                      │                                     │
         │    ┌─────────────────────────────────┴──────────────────────────────┐     │
         │    │                     feature/*                                   │     │
         │    │                   (new features)                                │     │
         │    └────────────────────────────────────────────────────────────────┘     │
         │                                                                            │
         └────────────────────────────────────────────────────────────────────────────┘
```

### Branch → Environment Mapping

| Branch | Triggers | Deploys To | Pipeline | Approval |
|--------|----------|------------|----------|----------|
| `feature/*` | PR to develop | None (tests only) | Bitbucket only | Code review |
| `develop` | Merge from feature | **DEV** (auto) | Simple ECS update | None |
| `release/*` | Created from develop | **TEST → STAGING → PROD** | CodePipeline (B/G) | Manual at each stage |
| `hotfix/*` | Created from main | **PROD** (fast track) | CodePipeline (B/G) | Manual |
| `main` | Merge from release/hotfix | None (tag only) | N/A | N/A |

### Two Deployment Paths

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              TWO PATHS                                       │
├──────────────────────────────────┬──────────────────────────────────────────┤
│                                  │                                          │
│   DEV PATH (Fast)                │   RELEASE PATH (Formal)                  │
│   ─────────────────              │   ──────────────────────                 │
│                                  │                                          │
│   develop branch                 │   release/* branch                       │
│        │                         │        │                                 │
│        ▼                         │        ▼                                 │
│   Bitbucket: test + build        │   Bitbucket: test + build                │
│        │                         │        │                                 │
│        ▼                         │        ▼                                 │
│   ECR: push :dev tag             │   ECR: push :rc-* tag                    │
│        │                         │        │                                 │
│        ▼                         │        ▼                                 │
│   EventBridge → Lambda           │   EventBridge → CodePipeline             │
│        │                         │        │                                 │
│        ▼                         │        ▼                                 │
│   ┌─────────┐                    │   ┌─────────┐                            │
│   │   DEV   │ (auto, no gates)   │   │  TEST   │ (B/G, auto)                │
│   └─────────┘                    │   └────┬────┘                            │
│                                  │        │ [Tests + Approval]              │
│   • No SOC2 audit needed         │        ▼                                 │
│   • Fast iteration               │   ┌─────────┐                            │
│   • Developer testing            │   │ STAGING │ (B/G)                      │
│                                  │   └────┬────┘                            │
│                                  │        │ [Tests + Approval]              │
│                                  │        ▼                                 │
│                                  │   ┌─────────┐                            │
│                                  │   │  PROD   │ (B/G, linear rollout)      │
│                                  │   └─────────┘                            │
│                                  │                                          │
│                                  │   • SOC2 audit trail                     │
│                                  │   • Manual approvals                     │
│                                  │   • Auto rollback on failure             │
│                                  │                                          │
└──────────────────────────────────┴──────────────────────────────────────────┘
```

### GitFlow Workflow

```
1. FEATURE DEVELOPMENT
   ────────────────────

   develop ─────────────────────────────────────────────>
              \                                    /
               \──> feature/login ───> PR ───────/
                    │
                    └── Bitbucket: tests only (no deploy)


2. INTEGRATION (DEV)
   ──────────────────

   develop ──────────────────────────────────────────────>
                │
                └── Merge triggers: build → ECR → DEV deploy (auto)


3. RELEASE CANDIDATE (TEST → STAGING → PROD)
   ──────────────────────────────────────────

   develop ────────────────────────────────────────────────>
              \
               \──> release/1.2.0 ─────────────────────────>
                    │
                    ├── Push triggers: build → ECR
                    │
                    └── CodePipeline: TEST ──[approve]──> STAGING ──[approve]──> PROD

   main ───────────────────────────────────────────────────>
                                                       /
              <── merge + tag v1.2.0 ─────────────────/


4. HOTFIX (Emergency)
   ───────────────────

   main ────────────────────────────────────────────────────>
           \                                            /
            \──> hotfix/critical-bug ──────────────────/
                 │
                 └── CodePipeline: skip TEST/STAGING ──[approve]──> PROD
```

### Updated Pipeline for GitFlow

```yaml
# bitbucket-pipelines.yml (GitFlow version)

pipelines:
  # Feature branches: test only
  branches:
    'feature/*':
      - step: *test

  # Develop: test + build + deploy to DEV
    develop:
      - step: *test
      - step:
          <<: *build-and-push
          script:
            - # ... build and tag as :dev

  # Release branches: test + build → triggers full pipeline
    'release/*':
      - step: *test
      - step:
          <<: *build-and-push
          script:
            - # ... build and tag as :rc-{version}

  # Hotfix: test + build → triggers prod pipeline
    'hotfix/*':
      - step: *test
      - step:
          <<: *build-and-push
          script:
            - # ... build and tag as :hotfix-{sha}
```

### Image Tagging Strategy

| Branch | Image Tag | Example |
|--------|-----------|---------|
| `develop` | `dev`, `{sha}` | `my-app:dev`, `my-app:abc123f` |
| `release/1.2.0` | `rc-1.2.0`, `{sha}` | `my-app:rc-1.2.0`, `my-app:def456a` |
| `hotfix/*` | `hotfix-{sha}` | `my-app:hotfix-789xyz` |
| `main` (post-merge) | `v1.2.0`, `latest` | `my-app:v1.2.0`, `my-app:latest` |

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DEVELOPER WORKFLOW                              │
└─────────────────────────────────────────────────────────────────────────────┘

     Developer          Bitbucket              AWS ECR            AWS CodePipeline
         │                  │                     │                      │
         │   git push       │                     │                      │
         ├─────────────────>│                     │                      │
         │                  │                     │                      │
         │                  │  ┌───────────────┐  │                      │
         │                  │  │ npm test      │  │                      │
         │                  │  │ npm lint      │  │                      │
         │                  │  │ docker build  │  │                      │
         │                  │  │ docker push   │──┼─────────────────────>│
         │                  │  └───────────────┘  │                      │
         │                  │                     │                      │
         │                  │                     │   EventBridge        │
         │                  │                     │   detects push       │
         │                  │                     │──────────────────────>
         │                  │                     │                      │
         │                  │                     │         Pipeline triggered
         │                  │                     │                      │
         │                  │                     │                      ▼
         │                  │                     │              ┌──────────────┐
         │                  │                     │              │ Deploy DEV   │
         │                  │                     │              └──────┬───────┘
         │                  │                     │                     │
         │                  │                     │              ┌──────▼───────┐
         │                  │                     │              │ Run Tests    │
         │                  │                     │              └──────┬───────┘
         │                  │                     │                     │
         │                  │                     │              ┌──────▼───────┐
         │                  │                     │              │ ⏸ APPROVAL   │
         │                  │                     │              │  (TEST)      │
         │                  │                     │              └──────┬───────┘
         │                  │                     │                     │
         │                  │                     │                    ...
         │                  │                     │                     │
         │                  │                     │              ┌──────▼───────┐
         │                  │                     │              │ ⏸ APPROVAL   │
         │                  │                     │              │  (PROD)      │
         │                  │                     │              └──────┬───────┘
         │                  │                     │                     │
         │                  │                     │              ┌──────▼───────┐
         │                  │                     │              │ Deploy PROD  │
         │                  │                     │              └──────────────┘
```

## Pipeline Stages

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            AWS CODEPIPELINE                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐   │
│  │ SOURCE  │───>│   DEV   │───>│  TEST   │───>│ STAGING │───>│  PROD   │   │
│  │  (ECR)  │    │         │    │         │    │         │    │         │   │
│  └─────────┘    └────┬────┘    └────┬────┘    └────┬────┘    └────┬────┘   │
│                      │              │              │              │         │
│                      ▼              ▼              ▼              ▼         │
│                 ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐   │
│                 │ Deploy  │    │ Deploy  │    │ Deploy  │    │ Deploy  │   │
│                 │  (auto) │    │         │    │         │    │         │   │
│                 └────┬────┘    └─────────┘    └─────────┘    └─────────┘   │
│                      │                                                      │
│                      ▼                                                      │
│                 ┌─────────┐                                                 │
│                 │ Integr. │                                                 │
│                 │ Tests   │                                                 │
│                 └────┬────┘                                                 │
│                      │                                                      │
│                      ▼                                                      │
│                 ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐   │
│                 │    ✓    │───>│ Approve │───>│ Approve │───>│ Approve │   │
│                 │  (auto) │    │ (manual)│    │ (manual)│    │(restrict)│  │
│                 └─────────┘    └─────────┘    └─────────┘    └─────────┘   │
│                                                                              │
│  Legend:  ✓ = automatic    ⏸ = manual approval required                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

## SOC2 Compliance

| Requirement | Implementation |
|-------------|----------------|
| **Audit Trail** | CodePipeline logs all approvals with IAM identity + timestamp |
| **Separation of Duties** | Different IAM roles for dev vs prod approvals |
| **Change Management** | Manual approvals required before prod |
| **Immutable Artifacts** | Docker images tagged by commit SHA |
| **Traceability** | Commit SHA → Image tag → Deployment → CloudWatch logs |

## File Structure

```
templates/ecs-cicd/
├── README.md                     # This file
├── bitbucket-pipelines.yml       # CI pipeline (build + push to ECR)
├── Dockerfile                    # Multi-stage Node.js container
├── buildspecs/
│   ├── integration-tests.yml     # CodeBuild: API/integration tests
│   └── e2e-tests.yml             # CodeBuild: Playwright E2E tests
└── terraform/
    ├── main.tf                   # IAM roles, S3 bucket, CodeBuild
    ├── codepipeline.tf           # 10-stage pipeline definition
    ├── eventbridge.tf            # ECR → Pipeline trigger
    ├── variables.tf              # Input variables
    ├── outputs.tf                # Resource ARNs
    └── terraform.tfvars.example  # Example configuration
```

## Quick Start

### Prerequisites

- AWS account with appropriate permissions
- Bitbucket repository
- Terraform >= 1.0
- AWS CLI configured

### 1. Set up ECR Repository

```bash
aws ecr create-repository --repository-name my-app
```

### 2. Create SNS Topic for Approvals

```bash
aws sns create-topic --name deployment-approvals
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT:deployment-approvals \
  --protocol email \
  --notification-endpoint your-team@company.com
```

### 3. Deploy Terraform

```bash
cd terraform/

# Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

# Deploy
terraform init
terraform plan
terraform apply
```

### 4. Configure Bitbucket

Add these repository variables in Bitbucket Settings → Repository variables:

| Variable | Example Value |
|----------|---------------|
| `AWS_ACCESS_KEY_ID` | `AKIA...` |
| `AWS_SECRET_ACCESS_KEY` | `wJalr...` |
| `AWS_REGION` | `us-east-1` |
| `ECR_REGISTRY` | `123456789012.dkr.ecr.us-east-1.amazonaws.com` |
| `ECR_REPO` | `my-app` |

### 5. Copy Files to Your App Repo

```bash
# Copy to your application repository
cp bitbucket-pipelines.yml /path/to/your-app/
cp Dockerfile /path/to/your-app/
cp -r buildspecs /path/to/your-app/
```

## How It Works

### CI (Bitbucket)

1. **PR opened** → Runs tests only
2. **Merge to main** → Tests + Docker build + Push to ECR

### CD (CodePipeline)

1. **ECR push detected** → EventBridge triggers pipeline
2. **DEV** → Auto-deploy, run integration tests
3. **TEST** → Manual approval, deploy, run E2E tests
4. **STAGING** → Manual approval, deploy
5. **PROD** → Manual approval (restricted IAM role), deploy

### Approval Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     APPROVAL NOTIFICATION                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  EventBridge ──> SNS Topic ──> Slack / Email                │
│                                                             │
│  "Pipeline my-app requires approval for TEST deployment"    │
│                                                             │
│  [Approve]  [Reject]                                        │
│                                                             │
│  Approved by: arn:aws:iam::123456789012:user/john.doe      │
│  Timestamp: 2024-01-15T14:32:00Z                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Customization

### Adding a New Environment

1. Add to `terraform.tfvars`:
```hcl
ecs_cluster_arns = {
  # ... existing
  uat = "arn:aws:ecs:us-east-1:123456789012:cluster/uat-cluster"
}
```

2. Add stage in `codepipeline.tf` (copy existing stage block)

### Restricting Prod Approvals

The Terraform creates IAM policies. To restrict who can approve prod:

```hcl
# In your IAM user/role policy
{
  "Effect": "Allow",
  "Action": "codepipeline:PutApprovalResult",
  "Resource": "arn:aws:codepipeline:*:*:my-app-pipeline/Approval-Prod"
}
```

### Adding Slack Notifications

```bash
# Create Lambda for Slack webhook
# Subscribe Lambda to SNS topic
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT:deployment-approvals \
  --protocol lambda \
  --notification-endpoint arn:aws:lambda:us-east-1:ACCOUNT:function:slack-notify
```

## Troubleshooting

### Pipeline not triggering

1. Check EventBridge rule is enabled
2. Verify ECR image tag matches rule (`latest`)
3. Check CloudWatch logs for EventBridge

### Approval not working

1. Verify IAM user has `codepipeline:PutApprovalResult` permission
2. Check SNS topic subscription is confirmed

### ECS deployment failing

1. Check task definition is valid
2. Verify ECS service exists
3. Check CloudWatch logs for container errors

## Related Documentation

- [AWS CodePipeline](https://docs.aws.amazon.com/codepipeline/)
- [AWS ECS](https://docs.aws.amazon.com/ecs/)
- [Bitbucket Pipelines](https://support.atlassian.com/bitbucket-cloud/docs/bitbucket-pipelines-configuration-reference/)
