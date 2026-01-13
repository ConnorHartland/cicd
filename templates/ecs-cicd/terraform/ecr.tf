# =============================================================================
# ECR Repository with Security Scanning
# =============================================================================
# Note: This creates the ECR repository. If your ECR repo already exists,
# you can import it or remove this file and reference it via data source.
# =============================================================================

resource "aws_ecr_repository" "app" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "IMMUTABLE" # SOC2: Immutable tags for audit trail

  # Enable image scanning on push
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "AES256"
    # For KMS encryption, use:
    # encryption_type = "KMS"
    # kms_key        = aws_kms_key.ecr.arn
  }

  tags = var.tags
}

# Lifecycle policy to manage image retention
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 release images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["rc-", "v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 5 dev images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["dev"]
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 3
        description  = "Keep last 3 hotfix images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["hotfix-"]
          countType     = "imageCountMoreThan"
          countNumber   = 3
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 4
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 5
        description  = "Keep only last 30 SHA-tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ECR Repository Policy (allow CodePipeline/CodeBuild to pull images)
resource "aws_ecr_repository_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPull"
        Effect = "Allow"
        Principal = {
          Service = [
            "codepipeline.amazonaws.com",
            "codebuild.amazonaws.com",
            "ecs-tasks.amazonaws.com"
          ]
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Enhanced Scanning with Amazon Inspector (Optional)
# ---------------------------------------------------------------------------
# Uncomment to enable continuous scanning with Amazon Inspector
# resource "aws_inspector2_enabler" "ecr" {
#   account_ids    = [data.aws_caller_identity.current.account_id]
#   resource_types = ["ECR"]
# }

# ---------------------------------------------------------------------------
# EventBridge Rule for ECR Scan Findings (Optional)
# ---------------------------------------------------------------------------
# Alerts when critical/high vulnerabilities are found
resource "aws_cloudwatch_event_rule" "ecr_scan_findings" {
  name        = "${var.app_name}-ecr-scan-findings"
  description = "Alert on critical/high ECR scan findings"

  event_pattern = jsonencode({
    source      = ["aws.ecr"]
    detail-type = ["ECR Image Scan State Change"]
    detail = {
      scan-status = ["COMPLETE"]
      repository-name = [var.ecr_repository_name]
      finding-severity-counts = {
        CRITICAL = [{ "numeric" : [">", 0] }]
      }
    }
  })

  tags = var.tags
}

# Send critical findings to SNS
resource "aws_cloudwatch_event_target" "ecr_scan_alert" {
  rule      = aws_cloudwatch_event_rule.ecr_scan_findings.name
  target_id = "SendToSNS"
  arn       = var.approval_sns_topic_arn

  input_transformer {
    input_paths = {
      repo     = "$.detail.repository-name"
      tag      = "$.detail.image-tags[0]"
      critical = "$.detail.finding-severity-counts.CRITICAL"
      high     = "$.detail.finding-severity-counts.HIGH"
    }
    input_template = "\"SECURITY ALERT: ECR scan found <critical> CRITICAL and <high> HIGH vulnerabilities in <repo>:<tag>\""
  }
}
