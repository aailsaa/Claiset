# NOTE: For grading you should use a remote backend (S3 + DynamoDB lock).
# This file is a scaffold. You'll also want Terraform to create the bucket + table
# (bootstrap step) or create them once, then enable this backend.
#
# terraform {
#   backend "s3" {
#     bucket         = "claiset-tf-state-<YOUR-UNIQUE-SUFFIX>"
#     key            = "envs/prod/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "claiset-tf-locks"
#     encrypt        = true
#   }
# }

