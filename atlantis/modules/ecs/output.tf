output "backend_execution_role_arn" {
  value = aws_iam_role.backend_execution_role.arn
}
output "backend_task_role_arn" {
  value = aws_iam_role.backend_task_role.arn
}
output "cluster_id" {
  value = aws_ecs_cluster.cluster.id
}
output "backend_service_sg_id" {
  value = aws_security_group.backend_service.id
} 
output "cluster_name" {
  value = aws_ecs_cluster.cluster.name
}