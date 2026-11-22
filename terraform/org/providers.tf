provider "aws" {
  region = var.primary_region
  default_tags {
    tags = {
      Project   = "guardrails"
      ManagedBy = "terraform"
    }
  }
}
