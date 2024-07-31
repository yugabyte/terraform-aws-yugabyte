##########################################################
#
# Default values for creating a YugabyteDB cluster on AWS.
#
##########################################################

variable "associate_public_ip_address" {
  description = "Associate public IP address to instances created."
  default     = true
  type        = string
}

variable "cluster_name" {
  description = "The name for the cluster (universe) being created."
  type        = string
}

variable "custom_security_group_id" {
  description = "Security group to assign to the instances. Example: 'sg-12345'."
  default     = ""
  type        = string
}

variable "instance_type" {
  description = "The type of instances to create."
  default     = "c4.xlarge"
  type        = string
}

variable "num_instances" {
  description = "Number of instances in the YugaByte cluster."
  default     = "3"
  type        = string
}

variable "prefix" {
  description = "Prefix prepended to all resources created."
  default     = "yb-"
  type        = string
}

variable "replication_factor" {
  description = "The replication factor for the universe."
  default     = 3
  type        = string
}

variable "root_volume_iops" {
  description = "Provisioned IOPS - valid only for 'io1' type."
  default     = 0
  type        = string
}

variable "root_volume_size" {
  description = "The volume size in gigabytes."
  default     = "50"
  type        = string
}

variable "root_volume_type" {
  description = "The volume type. Must be one of 'gp2' or 'io1'."
  default     = "gp2"
  type        = string
}

variable "ssh_keypair" {
  description = "The SSH keypair name to use for the instances."
  type        = string
}

variable "ssh_private_key" {
  description = "The private key to use when connecting to the instances."
  type        = string
}

variable "ssh_user" {
  description = "The public key to use when connecting to the instances."
  type        = string
  default     = "centos"
}

variable "region_name" {
  description = "Region name for AWS. Example: 'us-west-2'"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones to utilize. Example: ['us-west-1a','us-west-1b','us-west-1c']"
  type        = list(string)
}

variable "subnet_ids" {
  description = "List of subnets to launch the instances in. Example: ['subnet-12345','subnet-98765']."
  type        = list(string)
}

variable "use_public_ip_for_ssh" {
  description = "Flag to control use of public or private ips for ssh."
  default     = "true"
  type        = string
}

variable "vpc_id" {
  description = "The VPC ID to create the security groups in."
  type        = string
}

variable "yb_download_url" {
  description = "The download location of the YugaByteDB edition"
  default     = "https://downloads.yugabyte.com"
  type        = string
}

variable "yb_version" {
  description = "The version number of YugaByteDB to install"
  default     = "2024.1.1.0"
  type        = string
}

variable "allowed_sources" {
  description = "Add Source IP in Security Group to restrict the traffic"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

