module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = "${var.name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  # Workers sit in private subnets and reach the internet (ECR, STS, EKS API) via NAT.
  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Public subnets only host the internet-facing ALB, nothing gets a public IP automatically.
  map_public_ip_on_launch = false

  # Guardrail: the VPC's default security group allows nothing.
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  # Guardrail: network audit trail in CloudWatch.
  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_cloudwatch_log_group_retention_in_days = var.log_retention_days
  flow_log_max_aggregation_interval               = 60
  vpc_flow_log_iam_role_name                      = "${var.name}-vpc-flow-log"
  vpc_flow_log_iam_policy_name                    = "${var.name}-vpc-flow-log"

  # Tags that let the AWS Load Balancer Controller discover subnets for ALBs.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
  tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}
