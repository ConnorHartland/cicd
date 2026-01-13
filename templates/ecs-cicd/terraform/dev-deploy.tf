# =============================================================================
# DEV Environment - Simple Auto-Deploy (No Pipeline)
# =============================================================================
# Triggered by: ECR push with :dev tag
# Action: Lambda updates ECS service to force new deployment
# =============================================================================

# EventBridge rule for :dev tag
resource "aws_cloudwatch_event_rule" "ecr_dev_push" {
  name        = "${var.app_name}-ecr-dev-push"
  description = "Trigger DEV deploy when :dev tag is pushed to ECR"

  event_pattern = jsonencode({
    source      = ["aws.ecr"]
    detail-type = ["ECR Image Action"]
    detail = {
      action-type     = ["PUSH"]
      result          = ["SUCCESS"]
      repository-name = [var.ecr_repository_name]
      image-tag       = ["dev"]
    }
  })

  tags = var.tags
}

# Lambda function for DEV deploy
resource "aws_lambda_function" "dev_deploy" {
  function_name = "${var.app_name}-dev-deploy"
  role          = aws_iam_role.dev_deploy_lambda.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 60

  filename         = data.archive_file.dev_deploy_lambda.output_path
  source_code_hash = data.archive_file.dev_deploy_lambda.output_base64sha256

  environment {
    variables = {
      ECS_CLUSTER = var.dev_ecs_cluster_name
      ECS_SERVICE = var.dev_ecs_service_name
    }
  }

  tags = var.tags
}

# Lambda code
data "archive_file" "dev_deploy_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda/dev-deploy.zip"

  source {
    content = <<-EOF
      const { ECSClient, UpdateServiceCommand } = require('@aws-sdk/client-ecs');

      exports.handler = async (event) => {
        console.log('ECR Push Event:', JSON.stringify(event, null, 2));

        const client = new ECSClient();
        const command = new UpdateServiceCommand({
          cluster: process.env.ECS_CLUSTER,
          service: process.env.ECS_SERVICE,
          forceNewDeployment: true,
        });

        try {
          const response = await client.send(command);
          console.log('ECS Update Response:', JSON.stringify(response, null, 2));
          return {
            statusCode: 200,
            body: JSON.stringify({ message: 'DEV deployment triggered' }),
          };
        } catch (error) {
          console.error('Error:', error);
          throw error;
        }
      };
    EOF
    filename = "index.js"
  }
}

# IAM role for Lambda
resource "aws_iam_role" "dev_deploy_lambda" {
  name = "${var.app_name}-dev-deploy-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "dev_deploy_lambda" {
  name = "${var.app_name}-dev-deploy-lambda-policy"
  role = aws_iam_role.dev_deploy_lambda.id

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
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ]
        Resource = "*"
      }
    ]
  })
}

# EventBridge target - Lambda
resource "aws_cloudwatch_event_target" "dev_deploy" {
  rule      = aws_cloudwatch_event_rule.ecr_dev_push.name
  target_id = "TriggerDevDeploy"
  arn       = aws_lambda_function.dev_deploy.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "dev_deploy" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dev_deploy.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecr_dev_push.arn
}
