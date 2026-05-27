# EventBridge Scheduler（旧EventBridge Rulesのスケジュール方式＝レガシーからの移行先）
# Schedulerは対象を呼び出すために専用のIAMロールをAssumeする（Lambdaのリソースベース権限は不要）。

resource "aws_iam_role" "scheduler_role" {
  name = "${var.project_name}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
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
      Resource = aws_lambda_function.notifier.arn
    }]
  })
}

resource "aws_scheduler_schedule" "schedule" {
  name        = "${var.project_name}-schedule"
  description = "AWS What's Newの定期取得トリガー（毎時0分）"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = "Asia/Tokyo"

  target {
    arn      = aws_lambda_function.notifier.arn
    role_arn = aws_iam_role.scheduler_role.arn
  }
}
