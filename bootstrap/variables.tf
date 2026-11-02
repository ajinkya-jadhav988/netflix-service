variable "region" {
  description = "AWS region for the state bucket and the app."
  type        = string
  default     = "ap-south-1"
}

variable "name" {
  description = "Name prefix. Must match var.name in infra/ (default netflix) because the deploy role's IAM scope uses it."
  type        = string
  default     = "netflix"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,15}$", var.name))
    error_message = "name must be 3-16 chars: lowercase letters, digits, hyphens, starting with a letter."
  }
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repository."
  type        = string
  default     = "ajinkya-jadhav988"
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
  default     = "netflix-service"
}

variable "github_environment" {
  description = "GitHub Environment whose jobs may assume the deploy role (create it in repo Settings > Environments and add required reviewers)."
  type        = string
  default     = "production"
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC identity provider. Set false if your AWS account already has one (only one is allowed per account)."
  type        = bool
  default     = true
}

variable "budget_email" {
  description = "Email address that receives AWS Budget cost alerts."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_email))
    error_message = "budget_email must be a valid email address."
  }
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget in USD. Alerts fire at 50% and 80% actual and 100% forecasted spend."
  type        = number
  default     = 50
}

variable "deploy_role_admin_access" {
  description = "Escape hatch: attach AdministratorAccess to the deploy role instead of the scoped policy. Leave false unless debugging an AccessDenied."
  type        = bool
  default     = false
}
