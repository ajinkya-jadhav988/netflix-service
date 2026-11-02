output "tf_state_bucket" {
  description = "S3 bucket holding the Terraform state of infra/."
  value       = aws_s3_bucket.tfstate.bucket
}

output "tf_state_kms_key_arn" {
  description = "KMS key that encrypts the state bucket (GitHub variable TF_STATE_KMS_KEY_ARN)."
  value       = aws_kms_key.tfstate.arn
}

output "aws_region" {
  description = "Region used by the pipelines."
  value       = var.region
}

output "plan_role_arn" {
  description = "Read-only role for PR plans (GitHub variable AWS_PLAN_ROLE_ARN)."
  value       = aws_iam_role.plan.arn
}

output "deploy_role_arn" {
  description = "Deploy role for the protected environment (GitHub variable AWS_DEPLOY_ROLE_ARN)."
  value       = aws_iam_role.deploy.arn
}

output "github_variables_cli" {
  description = "Copy-paste these (GitHub CLI) to configure the repository variables. No secrets are needed."
  value       = <<-EOT
    gh variable set AWS_REGION          --repo ${local.github_repo_ref} --body "${var.region}"
    gh variable set TF_STATE_BUCKET     --repo ${local.github_repo_ref} --body "${aws_s3_bucket.tfstate.bucket}"
    gh variable set TF_STATE_KMS_KEY_ARN --repo ${local.github_repo_ref} --body "${aws_kms_key.tfstate.arn}"
    gh variable set AWS_PLAN_ROLE_ARN   --repo ${local.github_repo_ref} --body "${aws_iam_role.plan.arn}"
    gh variable set AWS_DEPLOY_ROLE_ARN --repo ${local.github_repo_ref} --body "${aws_iam_role.deploy.arn}"
  EOT
}
