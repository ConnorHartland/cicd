terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}

# Note: ECR repository is created in ecr.tf
# If using an existing repo, uncomment below and comment out ecr.tf
# data "aws_ecr_repository" "app" {
#   name = var.ecr_repository_name
# }

# S3 bucket for pipeline artifacts
resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket = "${var.app_name}-pipeline-artifacts-${data.aws_caller_identity.current.account_id}"

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

# IAM role for CodePipeline
resource "aws_iam_role" "codepipeline" {
  name = "${var.app_name}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "${var.app_name}-codepipeline-policy"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts.arn,
          "${aws_s3_bucket.pipeline_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:DescribeImages",
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.approval_sns_topic_arn
      },
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:GetApplication",
          "codedeploy:GetApplicationRevision",
          "codedeploy:RegisterApplicationRevision"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "*"
        Condition = {
          StringEqualsIfExists = {
            "iam:PassedToService" = [
              "ecs-tasks.amazonaws.com",
              "codedeploy.amazonaws.com"
            ]
          }
        }
      }
    ]
  })
}

# IAM role for CodeBuild
resource "aws_iam_role" "codebuild" {
  name = "${var.app_name}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${var.app_name}-codebuild-policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts.arn,
          "${aws_s3_bucket.pipeline_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeImageScanFindings",
          "ecr:DescribeImages"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:${var.app_name}/*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# CodeBuild project for Security Gate (ECR scan check)
# ---------------------------------------------------------------------------
resource "aws_codebuild_project" "security_gate" {
  name          = "${var.app_name}-security-gate"
  description   = "Verify ECR scan results before deployment"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 15

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "ECR_REPOSITORY"
      value = var.ecr_repository_name
    }

    environment_variable {
      name  = "AWS_REGION"
      value = var.aws_region
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<-EOF
      version: 0.2
      phases:
        build:
          commands:
            - echo "Checking ECR scan results for $ECR_REPOSITORY"
            - |
              # Get the image tag from the source artifact
              IMAGE_TAG=$(cat imageDetail.json | jq -r '.ImageTags[0]')
              echo "Checking image tag: $IMAGE_TAG"

              # Wait for scan to complete (max 5 minutes)
              for i in {1..30}; do
                SCAN_STATUS=$(aws ecr describe-image-scan-findings \
                  --repository-name $ECR_REPOSITORY \
                  --image-id imageTag=$IMAGE_TAG \
                  --query 'imageScanStatus.status' \
                  --output text 2>/dev/null || echo "IN_PROGRESS")

                if [ "$SCAN_STATUS" = "COMPLETE" ]; then
                  break
                fi
                echo "Scan status: $SCAN_STATUS - waiting..."
                sleep 10
              done

              # Get scan findings
              FINDINGS=$(aws ecr describe-image-scan-findings \
                --repository-name $ECR_REPOSITORY \
                --image-id imageTag=$IMAGE_TAG)

              CRITICAL=$(echo $FINDINGS | jq -r '.imageScanFindings.findingSeverityCounts.CRITICAL // 0')
              HIGH=$(echo $FINDINGS | jq -r '.imageScanFindings.findingSeverityCounts.HIGH // 0')

              echo "=== ECR Scan Results ==="
              echo "CRITICAL: $CRITICAL"
              echo "HIGH: $HIGH"
              echo "========================"

              # Fail if critical vulnerabilities found
              if [ "$CRITICAL" -gt 0 ]; then
                echo "ERROR: $CRITICAL CRITICAL vulnerabilities found!"
                echo "Review findings in ECR console and fix before deploying."
                exit 1
              fi

              # Warn on high vulnerabilities (configurable to fail)
              if [ "$HIGH" -gt 5 ]; then
                echo "WARNING: $HIGH HIGH vulnerabilities found!"
                echo "Consider fixing before production deployment."
                # Uncomment to fail on high vulns: exit 1
              fi

              echo "Security gate PASSED"
    EOF
  }

  tags = var.tags
}

# CodeBuild project for integration tests
resource "aws_codebuild_project" "integration_tests" {
  name          = "${var.app_name}-integration-tests"
  description   = "Integration tests for ${var.app_name}"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspecs/integration-tests.yml"
  }

  tags = var.tags
}

# CodeBuild project for E2E tests
resource "aws_codebuild_project" "e2e_tests" {
  name          = "${var.app_name}-e2e-tests"
  description   = "E2E tests for ${var.app_name}"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 60

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_MEDIUM"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspecs/e2e-tests.yml"
  }

  tags = var.tags
}
