output "pipeline_name" {
  description = "Name of the CodePipeline"
  value       = aws_codepipeline.main.name
}

output "pipeline_arn" {
  description = "ARN of the CodePipeline"
  value       = aws_codepipeline.main.arn
}

output "artifact_bucket" {
  description = "S3 bucket for pipeline artifacts"
  value       = aws_s3_bucket.pipeline_artifacts.bucket
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.ecr_push.arn
}

output "codebuild_integration_project" {
  description = "CodeBuild project for integration tests"
  value       = aws_codebuild_project.integration_tests.name
}

output "codebuild_e2e_project" {
  description = "CodeBuild project for E2E tests"
  value       = aws_codebuild_project.e2e_tests.name
}
