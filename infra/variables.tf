variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "name" {
  description = "Name prefix for every resource. The CI deploy role's IAM permissions are scoped to this prefix, so change both together."
  type        = string
  default     = "netflix"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,15}$", var.name))
    error_message = "name must be 3-16 chars: lowercase letters, digits, hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment label used in tags."
  type        = string
  default     = "prod"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Keep within EKS standard support to avoid extended-support surcharges."
  type        = string
  default     = "1.35"

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.35."
  }
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "az_count" {
  description = "Number of Availability Zones (EKS and ALB need at least 2)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "single_nat_gateway" {
  description = "true = one shared NAT gateway (cheap, ~USD 32/month, single-AZ egress). false = one per AZ (highly available, more expensive)."
  type        = bool
  default     = true
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND (stable) or SPOT (cheaper, can be interrupted)."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes (hard ceiling that also caps cost)."
  type        = number
  default     = 3

  validation {
    condition     = var.node_max_size <= 6
    error_message = "node_max_size is capped at 6 as a cost guardrail. Edit this validation if you really need more."
  }
}

variable "node_desired_size" {
  description = "Initial number of worker nodes."
  type        = number
  default     = 2
}

variable "node_disk_size_gb" {
  description = "Root EBS volume size per node (encrypted gp3)."
  type        = number
  default     = 20
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the PUBLIC EKS API endpoint. GitHub-hosted runners use wide, changing IP ranges, so the default is open (IAM auth is still required). Restrict it if you use self-hosted runners."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "log_retention_days" {
  description = "Retention for EKS control-plane and VPC flow logs in CloudWatch."
  type        = number
  default     = 30
}

variable "deploy_role_name" {
  description = "Name of the GitHub Actions deploy role created by bootstrap/. It is granted Kubernetes cluster-admin through an EKS access entry."
  type        = string
  default     = "netflix-github-deploy"
}

variable "extra_admin_arns" {
  description = "Additional IAM role ARNs (e.g. your own admin role) that get Kubernetes cluster-admin. Use the plain role ARN, WITHOUT the /aws-reserved/sso.amazonaws.com/ path for Identity Center roles."
  type        = list(string)
  default     = []
}

variable "ecr_force_delete" {
  description = "Allow terraform destroy to delete ECR repositories that still contain images."
  type        = bool
  default     = true
}

variable "ecr_keep_last_images" {
  description = "How many images each ECR repository keeps (older ones expire via lifecycle policy)."
  type        = number
  default     = 20
}
