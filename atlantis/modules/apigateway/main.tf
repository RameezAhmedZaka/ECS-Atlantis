resource "aws_apigatewayv2_api" "atlantis" {
  name          = var.api_name
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.atlantis.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_vpc_link" "atlantis" {
  name               = var.vpc_link
  subnet_ids         = var.private_subnets
  security_group_ids = [aws_security_group.atlantis.id]
}

resource "aws_apigatewayv2_integration" "atlantis" {
  api_id                 = aws_apigatewayv2_api.atlantis.id
  integration_type       = var.integration_type
  integration_method     = var.integration_method
  connection_type        = var.connection_type
  connection_id          = aws_apigatewayv2_vpc_link.atlantis.id
  integration_uri        = var.lb_listener_arn
  payload_format_version = var.payload_format_version

  request_parameters = var.request_parameters
}



resource "aws_apigatewayv2_route" "atlantis_gui" {
  api_id    = aws_apigatewayv2_api.atlantis.id
  route_key = var.atlantis_gui_route_key
  target    = "integrations/${aws_apigatewayv2_integration.atlantis.id}"
}

resource "aws_apigatewayv2_route" "atlantis_proxy" {
  api_id    = aws_apigatewayv2_api.atlantis.id
  route_key = var.atlantis_proxy_route_key
  target    = "integrations/${aws_apigatewayv2_integration.atlantis.id}"
}

resource "aws_security_group" "atlantis" {
  name        = var.atlantis_sg_name
  description = var.atlantis_sg_description
  vpc_id      = var.vpc_id

  ingress {
    from_port   = var.from_port
    to_port     = var.to_port
    protocol    = var.protocol
    cidr_blocks = var.cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}