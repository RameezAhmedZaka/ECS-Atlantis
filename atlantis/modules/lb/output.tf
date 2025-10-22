output "lb_listener_arn" {
  value = aws_lb_listener.atlantis_listener.arn
}
output "target_group_arn" {
  value = aws_lb_target_group.atlantis_tg.arn
}

# output "lb_sg_id" {
#   value = aws_security_group.lb.id
# }