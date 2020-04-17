#
# Terraform module to create a YugaByte cluster on AWS.
#
# This script does not use an autoscaling group. It just
# creates the necessary machines and configures them.
#
# Required parameters:
#   region
#   cluster_name
#   ssh_keypair
#   ssh_private_key
#   subnet_ids
#   vpc_id
#
# Other useful options:
#   associate_public_ip_address [default: "true"]
#   custom_security_group_id
#   num_instances [default: 3]
#   
#


#########################################################
#
# Choose the most recent Amazon Linux AMI.
#
#########################################################

provider "aws" {
   region = var.region
}

data "aws_ami" "yugabyte_ami" {
  most_recent = true
  owners      = ["aws-marketplace"]

  filter {
    name = "name"

    values = [
      "CentOS Linux 7 x86_64 HVM EBS *",
    ]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}


#########################################################
#
# Create the security groups needed.
#
#########################################################

resource "aws_security_group" "yugabyte" {
  name   = "${var.prefix}${var.cluster_name}"
  vpc_id = "${var.vpc_id}"
  ingress {
    from_port = 7000
    to_port   = 7000
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 9000
    to_port   = 9000
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 6379
    to_port   = 6379
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 9042
    to_port   = 9042
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 5433
    to_port   = 5433
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 22
    to_port   = 22 
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 5422
    to_port   = 5422
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name      = "${var.prefix}${var.cluster_name}"
    YugaByte  = "true"
    Service   = "YugaByte"
  }
}

resource "aws_security_group" "yugabyte_intra" {
  name   = "${var.prefix}${var.cluster_name}-intra"
  vpc_id = "${var.vpc_id}"
  ingress {
    from_port = 7100
    to_port   = 7100
    protocol  = "tcp"
    self      = true
  }
  ingress {
    from_port = 9100
    to_port   = 9100
    protocol  = "tcp"
    self      = true
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name      = "${var.prefix}${var.cluster_name}-intra"
    YugaByte  = "true"
    Service   = "YugaByte"
  }
}

#########################################################
#
# Create the required nodes.
#
#########################################################

resource "aws_instance" "yugabyte_nodes" {
  count                       = "${var.num_instances}"
  ami                         = "${data.aws_ami.yugabyte_ami.id}"
  associate_public_ip_address = "${var.associate_public_ip_address}"
  instance_type               = "${var.instance_type}"
  key_name                    = "${var.ssh_keypair}"
  availability_zone           = "${element(var.availability_zones, count.index)}"
  subnet_id                   = "${element(var.subnet_ids, count.index)}"
  vpc_security_group_ids      = [
    "${aws_security_group.yugabyte.id}",
    "${aws_security_group.yugabyte_intra.id}"
  ]
  root_block_device {
    volume_size = "${var.root_volume_size}"
    volume_type = "${var.root_volume_type}"
    iops        = "${var.root_volume_iops}"
  }
  tags = {
    Name      = "${var.prefix}${var.cluster_name}-n${format("%d", count.index + 1)}"
    YugaByte  = "true"
    Service   = "YugaByte"
  }

  provisioner "file" {
    source = "${path.module}/utilities/scripts/install_software.sh"
    destination = "/home/${var.ssh_user}/install_software.sh"
    connection {
      host = "${self.public_ip}" 
      type = "ssh"
      user = "${var.ssh_user}"
      private_key = "${file(var.ssh_private_key)}"
    }
  }

  provisioner "file" {
    source = "${path.module}/utilities/scripts/create_universe.sh"
    destination = "/home/${var.ssh_user}/create_universe.sh"
    connection {
      host = "${self.public_ip}" 
      type = "ssh"
      user = "${var.ssh_user}"
      private_key = "${file(var.ssh_private_key)}"
    }
  }

  provisioner "file" {
    source = "${path.module}/utilities/scripts/start_tserver.sh"
    destination = "/home/${var.ssh_user}/start_tserver.sh"
    connection {
      host = "${self.public_ip}" 
      type = "ssh"
      user = "${var.ssh_user}"
      private_key = "${file(var.ssh_private_key)}"
    }
  }

  provisioner "file" {
    source = "${path.module}/utilities/scripts/start_master.sh"
    destination = "/home/${var.ssh_user}/start_master.sh"

    connection {
      host = "${self.public_ip}" 
      type = "ssh"
      user = "${var.ssh_user}"
      private_key = "${file(var.ssh_private_key)}"
    }
  }
  
  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/${var.ssh_user}/install_software.sh",
      "chmod +x /home/${var.ssh_user}/create_universe.sh",
      "chmod +x /home/${var.ssh_user}/start_tserver.sh",
      "chmod +x /home/${var.ssh_user}/start_master.sh",
      "sudo yum install -y wget",
      "/home/${var.ssh_user}/install_software.sh '${var.yb_version}'",
    ]
    connection {
      host = "${self.public_ip}" 
      type = "ssh"
      user = "${var.ssh_user}"
      private_key = "${file(var.ssh_private_key)}"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}


#########################################################
#
# Configure the nodes into a universe.
#
#########################################################

locals {
  ssh_ip_list="${var.use_public_ip_for_ssh == "true" ? join(" ", aws_instance.yugabyte_nodes.*.public_ip) : join(" ", aws_instance.yugabyte_nodes.*.private_ip)}"
  config_ip_list="${join(" ", aws_instance.yugabyte_nodes.*.private_ip)}"
  az_list="${join(" ", aws_instance.yugabyte_nodes.*.availability_zone)}"
}

resource "null_resource" "create_yugabyte_universe" {
  # Define the trigger condition to run the resource block
  triggers = {
    cluster_instance_ids = "${join(",", aws_instance.yugabyte_nodes.*.id)}" 
  }

  # Execute after the nodes are provisioned and the software installed.
  depends_on = ["aws_instance.yugabyte_nodes"]

  provisioner "local-exec" {
    # Bootstrap script called with private_ip of each node in the clutser
    command = "${path.module}/utilities/scripts/create_universe.sh 'aws' '${var.region_name}' ${var.replication_factor} '${local.config_ip_list}' '${local.ssh_ip_list}' '${local.az_list}' ${var.ssh_user} ${var.ssh_private_key}"
  }
}
