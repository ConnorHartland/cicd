# =============================================================================
# Common Variables
# =============================================================================

variable "app_name" {
  description = "Application name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "ecr_repository_name" {
  description = "ECR repository name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# DEV Environment (Simple Deploy - No Pipeline)
# =============================================================================

variable "dev_ecs_cluster_name" {
  description = "ECS cluster name for DEV environment"
  type        = string
}

variable "dev_ecs_service_name" {
  description = "ECS service name for DEV environment"
  type        = string
}

# =============================================================================
# Release Pipeline (TEST → STAGING → PROD)
# =============================================================================

variable "ecs_clusters" {
  description = "Map of environment to ECS cluster name (test, staging, prod)"
  type        = map(string)
  default = {
    test    = "test-cluster"
    staging = "staging-cluster"
    prod    = "prod-cluster"
  }
}

variable "ecs_services" {
  description = "Map of environment to ECS service name (test, staging, prod)"
  type        = map(string)
  default = {
    test    = "app-test"
    staging = "app-staging"
    prod    = "app-prod"
  }
}

# =============================================================================
# ALB and Target Groups (for Blue/Green deployments)
# =============================================================================

variable "alb_listeners" {
  description = "Map of environment to ALB listener ARN"
  type        = map(string)
}

variable "target_groups" {
  description = "Map of target group names (test_blue, test_green, staging_blue, etc.)"
  type        = map(string)
}

# =============================================================================
# Test Environment URLs
# =============================================================================

variable "test_environment_url" {
  description = "URL of TEST environment for integration tests"
  type        = string
}

variable "staging_environment_url" {
  description = "URL of STAGING environment for E2E tests"
  type        = string
}

# =============================================================================
# Approval Configuration
# =============================================================================

variable "approval_sns_topic_arn" {
  description = "SNS topic ARN for approval notifications"
  type        = string
}

variable "prod_approvers_iam_role" {
  description = "IAM role ARN that can approve prod deployments"
  type        = string
  default     = ""
}
