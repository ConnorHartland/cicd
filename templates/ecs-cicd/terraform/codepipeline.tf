# CodePipeline
resource "aws_codepipeline" "main" {
  name     = "${var.app_name}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  # Stage 1: Source (ECR)
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
        ImageTag       = "latest"
      }
    }
  }

  # Stage 2: Deploy to Dev (auto)
  stage {
    name = "Deploy-Dev"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ClusterName = var.ecs_cluster_arns["dev"]
        ServiceName = var.ecs_service_names["dev"]
        FileName    = "imagedefinitions.json"
      }
    }
  }

  # Stage 3: Integration Tests
  stage {
    name = "Test-Dev"

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
            name  = "SERVICE_URL"
            value = "https://dev.example.com"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  # Stage 4: Approval for Test
  stage {
    name = "Approval-Test"

    action {
      name     = "Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        NotificationArn = var.approval_sns_topic_arn
        CustomData      = "Please review and approve deployment to TEST environment"
      }
    }
  }

  # Stage 5: Deploy to Test
  stage {
    name = "Deploy-Test"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ClusterName = var.ecs_cluster_arns["test"]
        ServiceName = var.ecs_service_names["test"]
        FileName    = "imagedefinitions.json"
      }
    }
  }

  # Stage 6: E2E Tests
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
            value = "https://test.example.com"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  # Stage 7: Approval for Staging
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
        CustomData      = "Please review and approve deployment to STAGING environment"
      }
    }
  }

  # Stage 8: Deploy to Staging
  stage {
    name = "Deploy-Staging"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ClusterName = var.ecs_cluster_arns["staging"]
        ServiceName = var.ecs_service_names["staging"]
        FileName    = "imagedefinitions.json"
      }
    }
  }

  # Stage 9: Approval for Prod (restricted)
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
        CustomData      = "PRODUCTION DEPLOYMENT - Requires release-manager approval"
      }
    }
  }

  # Stage 10: Deploy to Prod
  stage {
    name = "Deploy-Prod"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ClusterName = var.ecs_cluster_arns["prod"]
        ServiceName = var.ecs_service_names["prod"]
        FileName    = "imagedefinitions.json"
      }
    }
  }

  tags = var.tags
}
