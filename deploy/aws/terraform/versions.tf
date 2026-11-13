terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
provider "aws" {
  region                      = var.region
  skip_credentials_validation = var.aws_emulator
  skip_requesting_account_id  = var.aws_emulator
  skip_metadata_api_check     = var.aws_emulator
  s3_use_path_style           = var.aws_emulator
  default_tags {
    tags = { Application = var.name }
  }
}
