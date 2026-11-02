data "aws_caller_identity" "current" {}

# Only AZs that are enabled by default (excludes Local Zones / opt-in regions).
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  cluster_name = "${var.name}-eks"
  azs          = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Private subnets (nodes + pods): /20 each. Public subnets (ALB only): /24 each.
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 200 + i)]

  deploy_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.deploy_role_name}"

  # Everyone in this map gets Kubernetes cluster-admin via EKS access entries.
  cluster_admins = merge(
    { github_deploy = local.deploy_role_arn },
    { for i, arn in var.extra_admin_arns : "extra_admin_${i}" => arn },
  )

  repositories = toset(["backend", "frontend"])
}
