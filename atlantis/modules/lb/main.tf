resource "aws_lb" "atlantis_nlb" {
  name               = var.lb_name
  internal           = var.internal
  load_balancer_type = var.load_balancer_type
  subnets            = var.public_subnets
}

resource "aws_lb_target_group" "atlantis_tg" {
  name        = var.target_group_name
  port        = var.port
  protocol    = var.protocol
  vpc_id      = var.vpc_id
  target_type = var.target_type
}

resource "aws_lb_listener" "atlantis_listener" {
  load_balancer_arn = aws_lb.atlantis_nlb.arn
  port              = var.listener_port
  protocol          = var.listener_protocol

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.atlantis_tg.arn
  }
}


# resource "aws_security_group" "lb" {
#   name   = var.lb_sg_name
#   vpc_id = var.vpc_id

#   ingress {
#     protocol    = "tcp"
#     from_port   = 80
#     to_port     = 80
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }