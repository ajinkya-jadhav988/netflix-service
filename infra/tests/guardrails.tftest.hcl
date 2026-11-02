# Offline unit test: plans the whole stack against a MOCKED AWS provider (no credentials, no cost) and
# asserts that the key guardrails are present. Run with:  cd infra && terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:sts::123456789012:assumed-role/test/session"
      user_id    = "AIDATEST"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition          = "aws"
      dns_suffix         = "amazonaws.com"
      reverse_dns_prefix = "com.amazonaws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name   = "ap-south-1"
      region = "ap-south-1"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Resource\":\"*\"}]}"
    }
  }

  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::123456789012:role/test"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:ap-south-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/MOCK"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:ap-south-1:123456789012:log-group:/mock"
    }
  }
}

run "guardrails_hold_with_defaults" {
  command = plan

  assert {
    condition     = alltrue([for r in aws_ecr_repository.app : r.image_tag_mutability == "IMMUTABLE"])
    error_message = "ECR tags must be immutable."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.app : r.image_scanning_configuration[0].scan_on_push])
    error_message = "ECR scan-on-push must be enabled."
  }

  assert {
    condition     = length(aws_ecr_repository.app) == 2
    error_message = "Expected one ECR repository for backend and one for frontend."
  }

  assert {
    condition     = output.region == "ap-south-1"
    error_message = "Default region should be ap-south-1."
  }
}

run "node_max_size_is_capped" {
  command = plan

  variables {
    node_max_size = 50
  }

  expect_failures = [var.node_max_size]
}

run "az_count_must_be_at_least_two" {
  command = plan

  variables {
    az_count = 1
  }

  expect_failures = [var.az_count]
}
