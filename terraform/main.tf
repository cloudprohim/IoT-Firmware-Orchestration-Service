terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "firmware_bucket" {
  bucket = "chpw-iot-firmware-${random_id.suffix.hex}"

  tags = {
    Project = "IoT-Firmware-Orchestration-Service"
    Purpose = "FirmwareStorage"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "chpw-iot-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Project = "IoT-Firmware-Orchestration-Service"
    Purpose = "LambdaExecutionRole"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3_access" {
  name = "chpw-iot-lambda-s3-access"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.firmware_bucket.arn,
          "${aws_s3_bucket.firmware_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_lambda_function" "orchestrator" {
  function_name = "chpw-iot-orchestrator"
  handler       = "orchestrator.lambda_handler"
  runtime       = "python3.11"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 10

  filename         = "${path.module}/../lambda/orchestrator.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda/orchestrator.zip")

  environment {
    variables = {
      FIRMWARE_BUCKET = aws_s3_bucket.firmware_bucket.bucket
    }
  }

  tags = {
    Project = "IoT-Firmware-Orchestration-Service"
    Purpose = "FirmwareOrchestrator"
  }
}

resource "aws_apigatewayv2_api" "firmware_api" {
  name          = "chpw-iot-firmware-api"
  protocol_type = "HTTP"

  tags = {
    Project = "IoT-Firmware-Orchestration-Service"
    Purpose = "FirmwareAPI"
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.firmware_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.orchestrator.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "check_update_route" {
  api_id    = aws_apigatewayv2_api.firmware_api.id
  route_key = "POST /firmware/check-update"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.firmware_api.id
  name        = "$default"
  auto_deploy = true

  tags = {
    Project = "IoT-Firmware-Orchestration-Service"
    Purpose = "DefaultStage"
  }
}

resource "aws_lambda_permission" "allow_apigw_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.firmware_api.execution_arn}/*/*"
}