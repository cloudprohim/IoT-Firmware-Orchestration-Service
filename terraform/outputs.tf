output "firmware_bucket_name" {
  value = aws_s3_bucket.firmware_bucket.bucket
}

output "lambda_function_name" {
  value = aws_lambda_function.orchestrator.function_name
}

output "lambda_role_name" {
  value = aws_iam_role.lambda_role.name
}

output "api_gateway_url" {
  value = aws_apigatewayv2_api.firmware_api.api_endpoint
}

output "firmware_check_endpoint" {
  value = "${aws_apigatewayv2_api.firmware_api.api_endpoint}/firmware/check-update"
}