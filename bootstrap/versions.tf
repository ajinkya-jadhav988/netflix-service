terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Deliberately NO remote backend: this stack creates the state bucket itself (chicken-and-egg),
  # so its own small state stays local in bootstrap/terraform.tfstate (git-ignored). Keep that file safe.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
