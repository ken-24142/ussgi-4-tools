output "lambda_function_name" {
  description = "Lambda関数名"
  value       = aws_lambda_function.notifier.function_name
}

output "dynamodb_table_name" {
  description = "重複防止テーブル名"
  value       = aws_dynamodb_table.processed_entries.name
}

output "slack_token_param_name" {
  description = "Slack Bot TokenのSSMパラメータ名（デプロイ後にここへ実値を設定）"
  value       = aws_ssm_parameter.slack_bot_token.name
}

output "slack_channel_param_name" {
  description = "Slack Channel IDのSSMパラメータ名（デプロイ後にここへ実値を設定）"
  value       = aws_ssm_parameter.slack_channel_id.name
}
