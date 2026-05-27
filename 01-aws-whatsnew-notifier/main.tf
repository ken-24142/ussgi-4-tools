terraform {
  required_version = ">= 1.14.1"

  backend "s3" {
    bucket       = "<bucket-name>"
    key          = "whatsnew/terraform.tfstate"
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

locals {
  # SSMパラメータ名は先頭を "aws" / "ssm" で始められない（AWS予約プレフィックス）。
  # project_name が "aws-" 等で始まる場合は除去して安全なプレフィックスにする。
  ssm_param_prefix = replace(var.project_name, "/^(aws|ssm)-?/", "")
}

resource "aws_dynamodb_table" "processed_entries" {
  name         = "${var.project_name}-processed-entries"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "entry_id"

  attribute {
    name = "entry_id"
    type = "S"
  }

  ttl {
    attribute_name = "expire_at"
    enabled        = true
  }
}

resource "aws_ssm_parameter" "slack_bot_token" {
  name        = "/${local.ssm_param_prefix}/slack/bot_token"
  description = "Slack Bot Token (xoxb-...). デプロイ後にAWSコンソールから手動で実値を設定すること。"
  type        = "SecureString"
  value       = "REPLACE_ME"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "slack_channel_id" {
  name        = "/${local.ssm_param_prefix}/slack/channel_id"
  description = "投稿先SlackチャンネルID (例: C0123456789)。デプロイ後に手動で実値を設定すること。"
  type        = "String"
  value       = "REPLACE_ME"

  lifecycle {
    ignore_changes = [value]
  }
}
