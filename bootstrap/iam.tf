# ---------------------------------------------------------------------------
# GitHub Actions -> AWS trust (OIDC). No long-lived AWS keys are stored in GitHub.
# ---------------------------------------------------------------------------
locals {
  github_oidc_url = "https://token.actions.githubusercontent.com"
  github_repo_ref = "${var.github_owner}/${var.github_repo}"
  oidc_provider_arn = (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )
  oidc_host = "token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = local.github_oidc_url
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = local.github_oidc_url
}

# --- Role 1: PLAN (read-only). Used by pull requests and the plan job. -----------------------
data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values = [
        "repo:${local.github_repo_ref}:pull_request",
        "repo:${local.github_repo_ref}:ref:refs/heads/*",
      ]
    }
  }
}

resource "aws_iam_role" "plan" {
  name               = "${var.name}-github-plan"
  description        = "GitHub Actions: read-only terraform plan"
  assume_role_policy = data.aws_iam_policy_document.plan_trust.json
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan_state" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.tfstate.arn]
  }

  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/${var.name}/*"]
  }

  # terraform plan takes a lock by writing a small *.tflock object; it never writes state.
  statement {
    sid       = "StateLockOnly"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/${var.name}/*.tflock"]
  }

  statement {
    sid       = "StateEncryptionKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.tfstate.arn]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "state-access"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state.json
}

# --- Role 2: DEPLOY. Only jobs that run in the protected GitHub Environment can assume it. ---
data "aws_iam_policy_document" "deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["repo:${local.github_repo_ref}:environment:${var.github_environment}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "${var.name}-github-deploy"
  description          = "GitHub Actions: terraform apply/destroy and app deployment"
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust.json
  max_session_duration = 7200 # EKS create/destroy can exceed the 1h default
}

locals {
  region = var.region
  prefix = var.name
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "TerraformStateBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.tfstate.arn]
  }

  statement {
    sid       = "TerraformStateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/${local.prefix}/*"]
  }

  statement {
    sid       = "Networking"
    actions   = ["ec2:*"]
    resources = ["*"]
  }

  statement {
    sid       = "ReadOnlyHelpers"
    actions   = ["elasticloadbalancing:Describe*", "autoscaling:Describe*"]
    resources = ["*"]
  }

  statement {
    sid       = "EksAndLogsAndKms"
    actions   = ["eks:*", "logs:*", "kms:*"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrRepositories"
    actions   = ["ecr:*"]
    resources = ["arn:aws:ecr:${local.region}:${local.account_id}:repository/${local.prefix}-*"]
  }

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EksOptimizedAmiLookup"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:${local.region}::parameter/aws/service/*"]
  }

  # IAM is limited to resources named "<prefix>-*" plus the cluster's OIDC provider.
  statement {
    sid     = "IamForPrefixedResources"
    actions = ["iam:*"]
    resources = [
      "arn:aws:iam::${local.account_id}:role/${local.prefix}-*",
      "arn:aws:iam::${local.account_id}:policy/${local.prefix}-*",
      "arn:aws:iam::${local.account_id}:instance-profile/${local.prefix}-*",
      "arn:aws:iam::${local.account_id}:oidc-provider/oidc.eks.${local.region}.amazonaws.com/id/*",
    ]
  }

  statement {
    sid       = "IamServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole", "iam:GetPolicy", "iam:GetPolicyVersion"]
    resources = ["arn:aws:iam::${local.account_id}:role/aws-service-role/*", "arn:aws:iam::aws:policy/*"]
  }

  # Guardrail: the pipeline can never edit its own roles/policies (blocks trivial privilege escalation).
  statement {
    sid    = "DenyEditingPipelineRoles"
    effect = "Deny"
    actions = [
      "iam:Attach*", "iam:Detach*", "iam:Put*", "iam:Delete*", "iam:Update*",
      "iam:TagRole", "iam:UntagRole", "iam:CreateRole",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:role/${local.prefix}-github-*",
    ]
  }

  # Guardrail: everything is pinned to one region.
  statement {
    sid       = "DenyOtherRegions"
    effect    = "Deny"
    actions   = ["ec2:*", "eks:*", "ecr:*", "logs:*", "kms:*"]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }
}

resource "aws_iam_role_policy" "deploy" {
  count = var.deploy_role_admin_access ? 0 : 1

  name   = "scoped-deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

resource "aws_iam_role_policy_attachment" "deploy_admin" {
  count = var.deploy_role_admin_access ? 1 : 0

  role       = aws_iam_role.deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
