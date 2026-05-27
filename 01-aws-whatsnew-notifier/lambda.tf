locals {
  lambda_source_dir = "${path.module}/lambda"
  lambda_build_dir  = "${path.module}/build"
  lambda_zip_path   = "${path.module}/build.zip"
}

# 依存パッケージをビルドフォルダに展開し、Pythonコードもコピー（PowerShell）
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
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.processed_entries.arn
      },
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/amazon.nova-lite-v1:0",
          "arn:aws:bedrock:*:*:inference-profile/apac.amazon.nova-lite-v1:0"
        ]
      },
      {
        Effect = "Allow"
        Action = ["ssm:GetParameter"]
        Resource = [
          aws_ssm_parameter.slack_bot_token.arn,
          aws_ssm_parameter.slack_channel_id.arn
        ]
      }
    ]
  })
}

resource "aws_lambda_function" "notifier" {
  function_name = var.project_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 256

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      RSS_URL             = var.rss_url
      DYNAMODB_TABLE      = aws_dynamodb_table.processed_entries.name
      BEDROCK_MODEL_ID    = var.bedrock_model_id
      SLACK_TOKEN_PARAM   = aws_ssm_parameter.slack_bot_token.name
      SLACK_CHANNEL_PARAM = aws_ssm_parameter.slack_channel_id.name
    }
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.notifier.function_name}"
  retention_in_days = 14
}
