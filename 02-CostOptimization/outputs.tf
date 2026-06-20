output "lambda_function_name" {
  description = "Lambda関数名"
  value       = aws_lambda_function.report.function_name
}

output "report_bucket_name" {
  description = "レポート保存先S3バケット名"
  value       = aws_s3_bucket.reports.id
}

output "accounts_object_uri" {
  description = "対象アカウント一覧JSONのS3 URI（デプロイ後、ここに実値を書き込む）"
  value       = "s3://${aws_s3_bucket.reports.id}/${var.accounts_object_key}"
}

output "reports_prefix_uri" {
  description = "レポート出力先のS3 URIプレフィックス"
  value       = "s3://${aws_s3_bucket.reports.id}/${var.reports_prefix}/"
}
