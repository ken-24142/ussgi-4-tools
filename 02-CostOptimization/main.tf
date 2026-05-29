terraform {
  required_version = ">= 1.14.1"

  backend "s3" {
    bucket       = "<bucket-name>"
    key          = "cost-optimization/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.35.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  # バケット名は全世界でユニークである必要があるため、アカウントIDを含める。
  report_bucket_name = coalesce(var.report_bucket_name, "${var.project_name}-${data.aws_caller_identity.current.account_id}")
}

resource "aws_s3_bucket" "reports" {
  bucket = local.report_bucket_name
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket = aws_s3_bucket.reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "reports" {
  bucket = aws_s3_bucket.reports.id

  versioning_configuration {
    status = "Enabled"
  }
}

# 対象AWSアカウント一覧のプレースホルダー。
# デプロイ後、コンソールやCLIで実値に書き換える運用。
# cost_2_months_ago / cost_prev_month は毎月手動で更新する。
# 一度作成したらTerraformで内容を上書きしないようにlifecycleで保護する。
resource "aws_s3_object" "accounts_json" {
  bucket       = aws_s3_bucket.reports.id
  key          = var.accounts_object_key
  content_type = "application/json"
  content      = jsonencode([
    {
      id                = "123456789012"
      name              = "REPLACE_ME_SampleAccount"
      cost_2_months_ago = 0
      cost_prev_month   = 0
    }
  ])

  lifecycle {
    ignore_changes = [content, content_base64, etag]
  }
}
