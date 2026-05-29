locals {
  lambda_source_dir = "${path.module}/lambda"
  lambda_build_dir  = "${path.module}/build"
  lambda_zip_path   = "${path.module}/build.zip"
}

# 依存パッケージをビルドフォルダに展開し、Pythonコードもコピー（PowerShell）。
# 今回はboto3のみ（Lambdaランタイム同梱）なので、requirements.txt が空でもpip installは無害に通る。
resource "null_resource" "lambda_build" {
  triggers = {
    source_code  = filemd5("${local.lambda_source_dir}/index.py")
    requirements = filemd5("${local.lambda_source_dir}/requirements.txt")
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = <<-EOT
      if (Test-Path "${local.lambda_build_dir}") { Remove-Item -Recurse -Force "${local.lambda_build_dir}" }
      New-Item -ItemType Directory -Force -Path "${local.lambda_build_dir}" | Out-Null
      pip install -r "${local.lambda_source_dir}/requirements.txt" -t "${local.lambda_build_dir}" --quiet
      Copy-Item "${local.lambda_source_dir}/index.py" "${local.lambda_build_dir}/"
    EOT
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = local.lambda_build_dir
  output_path = local.lambda_zip_path

  depends_on = [null_resource.lambda_build]
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_inline" {
  name = "${var.project_name}-lambda-inline"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # 対象アカウント一覧JSONの読み取り
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.reports.arn}/${var.accounts_object_key}"
      },
      # レポート（Markdown）書き込み
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.reports.arn}/${var.reports_prefix}/*"
      },
      # Cost Optimization Hub（COH委任管理者としてアカウント別の推奨を参照）
      # ※ 利用料は accounts.json から読むので Cost Explorer の権限は不要。
      {
        Effect = "Allow"
        Action = [
          "cost-optimization-hub:ListRecommendations",
          "cost-optimization-hub:GetRecommendation",
          "cost-optimization-hub:ListEnrollmentStatuses",
          "cost-optimization-hub:GetPreferences"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "report" {
  function_name = var.project_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  timeout       = 600
  memory_size   = 512

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      REPORT_BUCKET       = aws_s3_bucket.reports.id
      ACCOUNTS_KEY        = var.accounts_object_key
      REPORTS_PREFIX      = var.reports_prefix
      MAX_RECOMMENDATIONS = tostring(var.max_recommendations)
    }
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.report.function_name}"
  retention_in_days = 14
}
