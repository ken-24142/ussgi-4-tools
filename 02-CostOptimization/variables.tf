variable "region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "リソース名のprefixとして使うプロジェクト名"
  type        = string
  default     = "aws-cost-optimization-report"
}

variable "report_bucket_name" {
  description = "レポート保存先S3バケット名"
  type        = string
  default     = null
}

variable "accounts_object_key" {
  description = "S3バケット直下に置く、対象アカウント一覧JSONファイルのキー名"
  type        = string
  default     = "accounts.json"
}

variable "reports_prefix" {
  description = "レポート出力先のS3キーprefix"
  type        = string
  default     = "reports"
}

variable "schedule_expression" {
  description = "EventBridge Schedulerのスケジュール式"
  type        = string
  default     = "cron(0 9 1 * ? *)"
}

variable "max_recommendations" {
  description = "レポートに掲載する削減施策の最大件数"
  type        = number
  default     = 3
}
