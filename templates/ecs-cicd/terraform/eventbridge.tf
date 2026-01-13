# =============================================================================
# EventBridge Rules for Release Pipeline
# =============================================================================
# Triggers CodePipeline when :rc-* (release candidate) tags are pushed to ECR
# Note: DEV deploy rule is in dev-deploy.tf (triggers Lambda directly)
# =============================================================================

# EventBridge rule for :rc-* tags (release candidates)
resource "aws_cloudwatch_event_rule" "ecr_release_push" {
  name        = "${var.app_name}-ecr-release-push"
  description = "Trigger release pipeline when :rc-* tag is pushed to ECR"

  event_pattern = jsonencode({
    source      = ["aws.ecr"]
    detail-type = ["ECR Image Action"]
    detail = {
      action-type     = ["PUSH"]
      result          = ["SUCCESS"]
      repository-name = [var.ecr_repository_name]
      image-tag = [{
        prefix = "rc-"
      }]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "release_pipeline" {
  rule      = aws_cloudwatch_event_rule.ecr_release_push.name
  target_id = "TriggerReleasePipeline"
  arn       = aws_codepipeline.release.arn
  role_arn  = aws_iam_role.eventbridge_release.arn
}

# ---------------------------------------------------------------------------
# EventBridge rule for :hotfix-* tags (fast-track to prod)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "ecr_hotfix_push" {
  name        = "${var.app_name}-ecr-hotfix-push"
  description = "Trigger hotfix pipeline when :hotfix-* tag is pushed to ECR"

  event_pattern = jsonencode({
    source      = ["aws.ecr"]
    detail-type = ["ECR Image Action"]
    detail = {
      action-type     = ["PUSH"]
      result          = ["SUCCESS"]
      repository-name = [var.ecr_repository_name]
      image-tag = [{
        prefix = "hotfix-"
      }]
    }
  })

  tags = var.tags
}

# Hotfix can also trigger the release pipeline (same flow, different source)
resource "aws_cloudwatch_event_target" "hotfix_pipeline" {
  rule      = aws_cloudwatch_event_rule.ecr_hotfix_push.name
  target_id = "TriggerHotfixPipeline"
  arn       = aws_codepipeline.release.arn
  role_arn  = aws_iam_role.eventbridge_release.arn
}

# ---------------------------------------------------------------------------
# IAM Role for EventBridge to trigger CodePipeline
# ---------------------------------------------------------------------------
resource "aws_iam_role" "eventbridge_release" {
  name = "${var.app_name}-eventbridge-release-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "eventbridge_release" {
  name = "${var.app_name}-eventbridge-release-policy"
  role = aws_iam_role.eventbridge_release.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "codepipeline:StartPipelineExecution"
        Resource = aws_codepipeline.release.arn
      }
    ]
  })
}
