module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = local.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # workers + control-plane ENIs live in private subnets

  # API endpoint: public so GitHub-hosted runners can run kubectl/helm; IAM auth is always required.
  endpoint_public_access       = true
  endpoint_private_access      = true
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # Guardrail: access is managed only through EKS access entries (IAM), not the legacy aws-auth ConfigMap.
  authentication_mode = "API"

  # The identity running `terraform plan` (read-only role) differs from the one that applies,
  # so admin is granted explicitly to the deploy role instead of "whoever created the cluster".
  enable_cluster_creator_admin_permissions = false
  access_entries = {
    for key, arn in local.cluster_admins : key => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Guardrail: Kubernetes Secrets are envelope-encrypted with a customer-managed KMS key (auto-rotated).
  create_kms_key          = true
  enable_kms_key_rotation = true
  kms_key_administrators  = [local.deploy_role_arn]
  encryption_config       = { resources = ["secrets"] }

  # Guardrail: audit trail of everything that talks to the control plane.
  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  addons = {
    # CNI must exist before nodes join. enableNetworkPolicy turns on Kubernetes NetworkPolicy enforcement.
    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
    kube-proxy     = {}
    coredns        = {}
    metrics-server = {} # needed by the HorizontalPodAutoscaler and `kubectl top`
  }

  eks_managed_node_groups = {
    default = {
      name           = "${var.name}-nodes"
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      labels = {
        workload = "apps"
      }

      # Guardrail: encrypted root volume.
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.node_disk_size_gb
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      # Guardrail: IMDSv2 only, and pods cannot reach the node's instance metadata (hop limit 1).
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }

      # Guardrail: no SSH keys / no port 22. Use SSM Session Manager to get a shell on a node.
      iam_role_additional_policies = {
        ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }

      update_config = {
        max_unavailable = 1
      }
    }
  }
}
