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

variable "environments" {
  description = "List of environments to deploy to"
  type        = list(string)
  default     = ["dev", "test", "staging", "prod"]
}

variable "ecs_cluster_arns" {
  description = "Map of environment to ECS cluster ARN"
  type        = map(string)
}

variable "ecs_service_names" {
  description = "Map of environment to ECS service name"
  type        = map(string)
}

variable "approval_sns_topic_arn" {
  description = "SNS topic ARN for approval notifications"
  type        = string
}

variable "prod_approvers_iam_role" {
  description = "IAM role ARN that can approve prod deployments"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
