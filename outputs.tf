#########################################################
#
# Outputs for the YugabyteDB Terraform module.
#
#########################################################

output "master-ui" {
  sensitive = false
  value     = "http://${local.yugabyte_node_1_ip}:7000"
}

output "tserver-ui" {
  sensitive = false
  value     = "http://${local.yugabyte_node_1_ip}:9000"
}

output "public_ips" {
  sensitive = false
  value     = aws_instance.yugabyte_nodes.*.public_ip
}

output "private_ips" {
  sensitive = false
  value     = aws_instance.yugabyte_nodes.*.private_ip
}

output "instance_ids" {
  sensitive = false
  value     = aws_instance.yugabyte_nodes.*.id
}

output "security_group" {
  sensitive = false
  value     = aws_security_group.yugabyte.id
}

output "ssh_user" {
  sensitive = false
  value     = var.ssh_user
}

output "ssh_key" {
  sensitive = false
  value     = var.ssh_private_key
}

output "JDBC" {
  sensitive = false
  value     = "postgresql://yugabyte@${local.yugabyte_node_1_ip}:5433"
}

output "YSQL" {
  sensitive = false
  value     = "ysqlsh -U yugabyte -h ${local.yugabyte_node_1_ip} -p 5433"
}

output "YCQL" {
  sensitive = false
  value     = "ycqlsh ${local.yugabyte_node_1_ip} 9042"
}

output "YEDIS" {
  sensitive = false
  value     = "redis-cli -h ${local.yugabyte_node_1_ip} -p 6379"
}

