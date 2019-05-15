# terraform-aws-yugabyte
A Terraform module to deploy and run YugaByte on AWS.

## Config

```
module "yugabyte-db-cluster" {
  source = "./terraform-aws-yugabyte"

  # The name of the cluster to be created.
  cluster_name = "tf-test"

  # A custom security group to be passed so that we can connect to the nodes.
  custom_security_group_id="SECURITY_GROUP_HERE"

  # AWS key pair.
  ssh_keypair = "SSH_KEYPAIR_HERE"
  ssh_key_path = "SSH_KEY_PATH_HERE"

  # The vpc and subnet ids where the nodes should be spawned.
  region_name = "YOUR VPC REGION"
  vpc_id = "VPC_ID_HERE"
  availability_zones = "AZ_LIST_HERE"
  subnet_ids = ["SUBNET_ID_LIST_HERE"]

  # Replication factor.
  replication_factor = "3"

  # The number of nodes in the cluster, this cannot be lower than the replication factor.
  num_instances = "3"
}
```

**NOTE:** If you do not have a custom security group, you would need to remove the `${var.custom_security_group_id}` variable in `main.tf`, so that the `aws_instance` looks as follows:

```
resource "aws_instance" "yugabyte_nodes" {
  count                       = "${var.num_instances}"
  ...
  vpc_security_group_ids      = [
    "${aws_security_group.yugabyte.id}",
    "${aws_security_group.yugabyte_intra.id}",
    "${var.custom_security_group_id}"
  ]

```

## Usage

Init terraform first if you have not already done so.

```
$ terraform init
```

Now run the following to create the instances and bring up the cluster.

```
$ terraform apply
```

Once the cluster is created, you can go to the URL `http://<node ip or dns name>:7000` to view the UI. You can find the node's ip or dns by running the following:

```
terraform state show aws_instance.yugabyte_nodes[0]
```

You can access the cluster UI by going to any of the following URLs.

You can check the state of the nodes at any point by running the following command.

```
$ terraform show
```

To destroy what we just created, you can run the following command.

```
$ terraform destroy
```
