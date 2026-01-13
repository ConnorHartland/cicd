# =============================================================================
# Release Pipeline (TEST → STAGING → PROD)
# =============================================================================
# Triggered by: ECR push with :rc-* tag (release candidates)
# Blue/Green deployments via CodeDeploy
# =============================================================================

resource "aws_codepipeline" "release" {
  name     = "${var.app_name}-release-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  # ---------------------------------------------------------------------------
  # Stage 1: Source (ECR - :rc-* tags only)
  # ---------------------------------------------------------------------------
  stage {
    name = "Source"

    action {
      name             = "ECR"
      category         = "Source"
      owner            = "AWS"
      provider         = "ECR"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName = var.ecr_repository_name
        # Note: EventBridge filters for :rc-* tags, but ECR source needs a specific tag
        # Use imageDetail.json from the event for dynamic tag
        ImageTag = "latest" # Overridden by EventBridge event
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Stage 2: Security Gate (ECR Scan Check)
  # ---------------------------------------------------------------------------
  stage {
    name = "Security-Gate"

    action {
      name             = "CheckECRScan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["security_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.security_gate.name
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Stage 3: Deploy to TEST (Blue/Green, auto)
  # ---------------------------------------------------------------------------
  stage {
    name = "Deploy-Test"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ApplicationName                = aws_codedeploy_app.main.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.test.deployment_group_name
        TaskDefinitionTemplateArtifact = "source_output"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "source_output"
        AppSpecTemplatePath            = "appspec.yaml"
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Stage 4: Integration Tests
  # ---------------------------------------------------------------------------
  stage {
    name = "Test-Integration"

    action {
      name             = "IntegrationTests"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["test_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.integration_tests.name
        EnvironmentVariables = jsonencode([
          {
            name  = "TARGET_URL"
            value = var.test_environment_url
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Stage 5: Approval for STAGING
  # ---------------------------------------------------------------------------
  stage {
    name = "Approval-Staging"

    action {
      name     = "Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        NotificationArn = var.approval_sns_topic_arn
        CustomData      = "Tests passed in TEST. Approve deployment to STAGING?"
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Stage 6: Deploy to STAGING (Blue/Green)
  # ---------------------------------------------------------------------------
  stage {
    name = "Deploy-Staging"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ApplicationName                = aws_codedeploy_app.main.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.staging.deployment_group_name
        TaskDefinitionTemplateArtifact = "source_output"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "source_output"
        AppSpecTemplatePath            = "appspec.yaml"
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Stage 7: E2E Tests
  # ---------------------------------------------------------------------------
  stage {
    name = "Test-E2E"

    action {
      name             = "E2ETests"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["e2e_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.e2e_tests.name
        EnvironmentVariables = jsonencode([
          {
            name  = "BASE_URL"
            value = var.staging_environment_url
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Stage 8: Approval for PROD (Restricted)
  # ---------------------------------------------------------------------------
  stage {
    name = "Approval-Prod"

    action {
      name     = "Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        NotificationArn = var.approval_sns_topic_arn
        CustomData      = "PRODUCTION DEPLOYMENT - E2E tests passed. Approve deployment to PROD?"
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Stage 9: Deploy to PROD (Blue/Green with linear rollout)
  # ---------------------------------------------------------------------------
  stage {
    name = "Deploy-Prod"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ApplicationName                = aws_codedeploy_app.main.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.prod.deployment_group_name
        TaskDefinitionTemplateArtifact = "source_output"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "source_output"
        AppSpecTemplatePath            = "appspec.yaml"
      }
    }
  }

  tags = var.tags
}
