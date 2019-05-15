#
# Terraform module to create a YugaByte cluster on AWS.
#
# This script does not use an autoscaling group. It just
# creates the necessary machines and configures them.
#
# Required parameters:
#   cluster_name
#   ssh_keypair
#   ssh_key_path
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

data "aws_ami" "yugabyte_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name = "name"

    values = [
      "amzn-ami-hvm-*-x86_64-gp2",
    ]
  }

  filter {
    name = "owner-alias"

    values = [
      "amazon",
    ]
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
    self      = true
  }
  ingress {
    from_port = 9000
    to_port   = 9000
    protocol  = "tcp"
    self      = true
  }
  ingress {
    from_port = 6379
    to_port   = 6379
    protocol  = "tcp"
    self      = true
  }
  ingress {
    from_port = 9042
    to_port   = 9042
    protocol  = "tcp"
    self      = true
  }
  ingress {
    from_port = 5433
    to_port   = 5433
    protocol  = "tcp"
    self      = true
  }
  lifecycle {
    create_before_destroy = true
  }
  tags {
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
  tags {
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
    "${aws_security_group.yugabyte_intra.id}",
    "${var.custom_security_group_id}"
  ]
  root_block_device {
    volume_size = "${var.root_volume_size}"
    volume_type = "${var.root_volume_type}"
    iops        = "${var.root_volume_iops}"
  }
  tags {
    Name      = "${var.prefix}${var.cluster_name}-n${format("%d", count.index + 1)}"
    YugaByte  = "true"
    Service   = "YugaByte"
  }

  provisioner "file" {
    source = "${path.module}/scripts/install_software.sh"
    destination = "/home/ec2-user/install_software.sh"
    connection {
      type = "ssh"
      user = "ec2-user"
      private_key = "${file(var.ssh_key_path)}"
    }
  }

  provisioner "file" {
    source = "${path.module}/scripts/create_universe.sh"
    destination = "/home/ec2-user/create_universe.sh"
    connection {
      type = "ssh"
      user = "ec2-user"
      private_key = "${file(var.ssh_key_path)}"
    }
  }

  provisioner "file" {
    source = "${path.module}/scripts/start_tserver.sh"
    destination = "/home/ec2-user/start_tserver.sh"
    connection {
      type = "ssh"
      user = "ec2-user"
      private_key = "${file(var.ssh_key_path)}"
    }
  }

  provisioner "file" {
    source = "${path.module}/scripts/start_master.sh"
    destination = "/home/ec2-user/start_master.sh"
    connection {
      type = "ssh"
      user = "ec2-user"
      private_key = "${file(var.ssh_key_path)}"
    }
  }
  
  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ec2-user/install_software.sh",
      "chmod +x /home/ec2-user/create_universe.sh",
      "chmod +x /home/ec2-user/start_tserver.sh",
      "chmod +x /home/ec2-user/start_master.sh",
      "/home/ec2-user/install_software.sh '${var.yb_edition}' '${var.yb_version}' '${var.yb_download_url}'",
    ]
    connection {
      type = "ssh"
      user = "ec2-user"
      private_key = "${file(var.ssh_key_path)}"
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

  # Execute after the nodes are provisioned and the software installed.
  depends_on = ["aws_instance.yugabyte_nodes"]

  provisioner "local-exec" {
    # Bootstrap script called with private_ip of each node in the clutser
    command = "${path.module}/scripts/create_universe.sh 'aws' '${var.region_name}' ${var.replication_factor} '${local.config_ip_list}' '${local.ssh_ip_list}' '${local.az_list}' ec2-user ${var.ssh_key_path}"
  }
}
