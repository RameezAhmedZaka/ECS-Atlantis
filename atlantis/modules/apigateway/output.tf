output "atlantis_url_gui" {
  value = "${data.aws_apigatewayv2_api.existing_api.api_endpoint}/prod/atlantis"
}

output "atlantis_url_webhook" {
  value = "${data.aws_apigatewayv2_api.existing_api.api_endpoint}/prod/atlantis/events"
}
output "sg_id" {
  value = aws_security_group.atlantis.id
}