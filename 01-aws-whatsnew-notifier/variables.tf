variable "region" {
  description = "AWSリージョン。BedrockのNova Lite（APAC推論プロファイル）が使えるリージョンを指定すること。"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "リソース名のprefixとして使うプロジェクト名"
  type        = string
  default     = "aws-whatsnew-notifier"
}

variable "bedrock_model_id" {
  description = "Bedrock model ID (クロスリージョン推論プロファイル)。Converse API経由で呼び出すのでClaude/Nova等の他モデルにも差し替え可能。"
  type        = string
  default     = "apac.amazon.nova-lite-v1:0"
}

variable "rss_url" {
  description = "AWS What's NewのRSS URL"
  type        = string
  default     = "https://aws.amazon.com/about-aws/whats-new/recent/feed/"
}

variable "schedule_expression" {
  description = "EventBridge Schedulerのスケジュール式。デフォルトは毎時0分。"
  type        = string
  default     = "cron(0 * * * ? *)"
}
