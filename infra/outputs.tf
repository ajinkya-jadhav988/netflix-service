output "region" {
  description = "AWS region of the deployment."
  value       = var.region
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "vpc_id" {
  description = "VPC ID (passed to the AWS Load Balancer Controller Helm chart)."
  value       = module.vpc.vpc_id
}

output "lbc_role_arn" {
  description = "IAM role ARN the AWS Load Balancer Controller service account assumes."
  value       = aws_iam_role.lbc.arn
}

output "ecr_repository_urls" {
  description = "ECR repository URLs keyed by app (backend, frontend)."
  value       = { for k, r in aws_ecr_repository.app : k => r.repository_url }
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at the cluster (your IAM role must be in extra_admin_arns)."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
