# EventBridge rule to trigger pipeline on ECR push
resource "aws_cloudwatch_event_rule" "ecr_push" {
  name        = "${var.app_name}-ecr-push"
  description = "Trigger CodePipeline when new image is pushed to ECR"

  event_pattern = jsonencode({
    source      = ["aws.ecr"]
    detail-type = ["ECR Image Action"]
    detail = {
      action-type     = ["PUSH"]
      result          = ["SUCCESS"]
      repository-name = [var.ecr_repository_name]
      image-tag       = ["latest"]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "codepipeline" {
  rule      = aws_cloudwatch_event_rule.ecr_push.name
  target_id = "TriggerCodePipeline"
  arn       = aws_codepipeline.main.arn
  role_arn  = aws_iam_role.eventbridge.arn
}

# IAM role for EventBridge to trigger CodePipeline
resource "aws_iam_role" "eventbridge" {
  name = "${var.app_name}-eventbridge-role"

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

resource "aws_iam_role_policy" "eventbridge" {
  name = "${var.app_name}-eventbridge-policy"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "codepipeline:StartPipelineExecution"
        Resource = aws_codepipeline.main.arn
      }
    ]
  })
}
