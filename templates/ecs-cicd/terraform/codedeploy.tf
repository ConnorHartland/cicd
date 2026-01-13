# =============================================================================
# CodeDeploy for Blue/Green ECS Deployments
# =============================================================================

# CodeDeploy Application
resource "aws_codedeploy_app" "main" {
  name             = "${var.app_name}-deploy"
  compute_platform = "ECS"

  tags = var.tags
}

# ---------------------------------------------------------------------------
# TEST Environment - Blue/Green (Immediate traffic shift)
# ---------------------------------------------------------------------------
resource "aws_codedeploy_deployment_group" "test" {
  app_name               = aws_codedeploy_app.main.name
  deployment_group_name  = "${var.app_name}-test"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"

  ecs_service {
    cluster_name = var.ecs_clusters["test"]
    service_name = var.ecs_services["test"]
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [var.alb_listeners["test"]]
      }

      target_group {
        name = var.target_groups["test_blue"]
      }

      target_group {
        name = var.target_groups["test_green"]
      }
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# STAGING Environment - Blue/Green (Immediate traffic shift)
# ---------------------------------------------------------------------------
resource "aws_codedeploy_deployment_group" "staging" {
  app_name               = aws_codedeploy_app.main.name
  deployment_group_name  = "${var.app_name}-staging"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"

  ecs_service {
    cluster_name = var.ecs_clusters["staging"]
    service_name = var.ecs_services["staging"]
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [var.alb_listeners["staging"]]
      }

      target_group {
        name = var.target_groups["staging_blue"]
      }

      target_group {
        name = var.target_groups["staging_green"]
      }
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# PROD Environment - Blue/Green (Linear 10% every 5 minutes)
# ---------------------------------------------------------------------------
resource "aws_codedeploy_deployment_group" "prod" {
  app_name               = aws_codedeploy_app.main.name
  deployment_group_name  = "${var.app_name}-prod"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = "CodeDeployDefault.ECSLinear10PercentEvery3Minutes"

  ecs_service {
    cluster_name = var.ecs_clusters["prod"]
    service_name = var.ecs_services["prod"]
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 60  # Keep old version for 1 hour for rollback
    }
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [var.alb_listeners["prod"]]
      }

      target_group {
        name = var.target_groups["prod_blue"]
      }

      target_group {
        name = var.target_groups["prod_green"]
      }
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  # Optional: CloudWatch alarms for auto-rollback
  # alarm_configuration {
  #   enabled = true
  #   alarms  = [var.prod_error_alarm_name]
  # }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# IAM Role for CodeDeploy
# ---------------------------------------------------------------------------
resource "aws_iam_role" "codedeploy" {
  name = "${var.app_name}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}
