#########################################################
#
# Outputs for the YugaByte terraform module.
#
#########################################################

output "ui" {
  sensitive = false
  value     = "http://${aws_instance.yugabyte_nodes.*.public_ip[0]}:7000"
}

output "hostname" {
  sensitive = false
  value     = ["${aws_instance.yugabyte_nodes.*.public_ip}"]
}

output "ip" {
  sensitive = false
  value     = ["${aws_instance.yugabyte_nodes.*.private_ip}"]
}

output "security_group" {
  sensitive = false
  value     = "${aws_security_group.yugabyte.id}"
}

output "ssh_key" {
  sensitive = false
  value     = "${var.ssh_keypair}"
}
