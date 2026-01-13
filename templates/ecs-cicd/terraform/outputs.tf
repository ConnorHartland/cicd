# =============================================================================
# DEV Deploy Outputs
# =============================================================================

output "dev_deploy_lambda_arn" {
  description = "ARN of the DEV deploy Lambda function"
  value       = aws_lambda_function.dev_deploy.arn
}

output "dev_eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for DEV deploys"
  value       = aws_cloudwatch_event_rule.ecr_dev_push.arn
}

# =============================================================================
# Release Pipeline Outputs
# =============================================================================

output "release_pipeline_name" {
  description = "Name of the release CodePipeline"
  value       = aws_codepipeline.release.name
}

output "release_pipeline_arn" {
  description = "ARN of the release CodePipeline"
  value       = aws_codepipeline.release.arn
}

output "artifact_bucket" {
  description = "S3 bucket for pipeline artifacts"
  value       = aws_s3_bucket.pipeline_artifacts.bucket
}

# =============================================================================
# EventBridge Outputs
# =============================================================================

output "release_eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for release pipeline"
  value       = aws_cloudwatch_event_rule.ecr_release_push.arn
}

output "hotfix_eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for hotfix pipeline"
  value       = aws_cloudwatch_event_rule.ecr_hotfix_push.arn
}

# =============================================================================
# CodeDeploy Outputs
# =============================================================================

output "codedeploy_app_name" {
  description = "Name of the CodeDeploy application"
  value       = aws_codedeploy_app.main.name
}

output "codedeploy_deployment_groups" {
  description = "CodeDeploy deployment group names by environment"
  value = {
    test    = aws_codedeploy_deployment_group.test.deployment_group_name
    staging = aws_codedeploy_deployment_group.staging.deployment_group_name
    prod    = aws_codedeploy_deployment_group.prod.deployment_group_name
  }
}

# =============================================================================
# CodeBuild Outputs
# =============================================================================

output "codebuild_security_gate_project" {
  description = "CodeBuild project for security gate (ECR scan check)"
  value       = aws_codebuild_project.security_gate.name
}

output "codebuild_integration_project" {
  description = "CodeBuild project for integration tests"
  value       = aws_codebuild_project.integration_tests.name
}

output "codebuild_e2e_project" {
  description = "CodeBuild project for E2E tests"
  value       = aws_codebuild_project.e2e_tests.name
}

# =============================================================================
# ECR Outputs
# =============================================================================

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.app.arn
}
