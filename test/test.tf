provider aws {
  region = "ap-southeast-1"
  default_tags {
    tags = {
      yb_owner = "yrampuria"
      yb_task = "test-tf"
      yb_dept = "sales"
      yb_project =  "terraform-aws-yugabyte"
      Terraform = "true"
      Environment = "dev"
    }
  }
}

module "yugabyte-db-cluster" {
  source = "../"
  cluster_name = "testtf"
  root_volume_type = "gp3"
  region_name = data.aws_region.current.name

  ssh_keypair = aws_key_pair.ssh-key.key_name
  ssh_private_key = local_file.ssh-key.filename
  vpc_id = module.infra.vpc_id
  availability_zones = local.azs
  subnet_ids = module.infra.public_subnets
  replication_factor = "3"
  num_instances = "3"
  tags = {
      yb_owner = "yrampuria"
      yb_task = "test-tf"
      yb_dept = "sales"
      yb_project =  "terraform-aws-yugabyte"
      Terraform = "true"
      Environment = "dev"
    }
}

output "outputs" {
  value = module.yugabyte-db-cluster
}


module "infra"{
  source = "terraform-aws-modules/vpc/aws"

  name = "test-vpc"
  cidr = "10.0.0.0/16"

  azs             = local.azs
  # private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = false
  # single_nat_gateway  = false

  default_security_group_name = "tftest"
  default_security_group_ingress = [
    {
      description      = "allow all"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = "0.0.0.0/0"
      ipv6_cidr_blocks = "::/0"
    }
  ]
  default_security_group_egress =  [
    {
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = "0.0.0.0/0"
      ipv6_cidr_blocks = "::/0"
    }
  ]
  default_security_group_tags =  {
      yb_owner = "yrampuria"
      yb_task = "test-tf"
      yb_dept = "sales"
      yb_project =  "terraform-aws-yugabyte"
      Terraform = "true"
      Environment = "dev"

    }
  # enable_vpn_gateway = true

  tags = {
  }
}

# RSA key of size 4096 bits
resource "tls_private_key" "ssh-key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ssh-key" {
  key_name_prefix = "tftest"
  public_key = tls_private_key.ssh-key.public_key_openssh
}
resource "local_file" "ssh-key" {
  content  = tls_private_key.ssh-key.private_key_pem
  filename = "${path.module}/sshkey.pem"
  file_permission = "0600"
}
data "aws_region" "current"{}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name = "zone-type"
    values = [ "availability-zone" ]
  }
}

locals {
  azs = slice(sort(distinct(data.aws_availability_zones.available.names)), 0,3)
}

