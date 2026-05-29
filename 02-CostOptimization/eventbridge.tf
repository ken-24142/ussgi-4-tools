# EventBridge Schedulerで月次実行。
# Schedulerは対象を呼び出すために専用のIAMロールをAssumeする（Lambdaのリソースベース権限は不要）。

resource "aws_iam_role" "scheduler_role" {
  name = "${var.project_name}-scheduler-role"

  # Confused Deputy対策として aws:SourceAccount 条件を付与し、
  # 同一アカウント内のSchedulerからのみAssumeを許可する。
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name = "${var.project_name}-scheduler-invoke"
  role = aws_iam_role.scheduler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.report.arn
    }]
  })
}

resource "aws_scheduler_schedule" "schedule" {
  name        = "${var.project_name}-schedule"
  description = "コスト最適化レポートの月次生成トリガー（毎月1日 09:00 JST）"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = "Asia/Tokyo"

  target {
    arn      = aws_lambda_function.report.arn
    role_arn = aws_iam_role.scheduler_role.arn
  }
}
