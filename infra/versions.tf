terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial backend configuration. bucket, region and kms_key_id are supplied at init time:
  #   terraform init -backend-config="bucket=<state-bucket>" -backend-config="region=<region>" \
  #                  -backend-config="kms_key_id=<kms-key-arn>"
  # use_lockfile = native S3 state locking (no DynamoDB table needed, Terraform >= 1.10).
  backend "s3" {
    key          = "netflix/infra.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
