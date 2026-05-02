# Bucket, key, lock table, and region are passed at init (see .github/workflows/promotion.yml).
terraform {
  backend "s3" {}
}
