provider "aws" {
  region = var.region

  # Every resource that supports tags gets these automatically (cost allocation + ownership).
  default_tags {
    tags = {
      Project     = var.name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "netflix-service"
    }
  }
}
