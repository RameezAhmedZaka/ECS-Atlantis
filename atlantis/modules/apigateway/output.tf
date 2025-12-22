output "atlantis_url_gui" {
  value = "${aws_apigatewayv2_api.atlantis.api_endpoint}/atlantis"
}

output "atlantis_url_webhook" {
  value = "${aws_apigatewayv2_api.atlantis.api_endpoint}/atlantis/events"
}
output "sg_id" {
  value = aws_security_group.atlantis.id
}