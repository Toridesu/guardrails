terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # bucket などは scripts/tf.sh が terraform/backend.hcl から渡す
  backend "s3" {}
}
