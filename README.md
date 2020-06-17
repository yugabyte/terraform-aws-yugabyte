# terraform-aws-yugabyte
A Terraform module to deploy and run YugaByte on AWS.

## Config

Save the following content to a terraform configuration file yb.tf

```
module "yugabyte-db-cluster" {
  source = ""github.com/YugaByte/terraform-aws-yugabyte"

  # The name of the cluster to be created.
  cluster_name = "tf-test"

  # Specify an existing AWS key pair
  # Both the name and the path to the corresponding private key file
  ssh_keypair = "SSH_KEYPAIR_HERE"     
  ssh_private_key = "SSH_KEY_PATH_HERE"

  # The vpc and subnet ids where the nodes should be spawned.
  region_name = "AWS REGION"
  vpc_id = "VPC_ID_HERE"
  availability_zones = ["AZ1", "AZ2", "AZ3"]
  subnet_ids = ["SUBNET_AZ1", SUBNET_AZ2", "SUBNET_AZ3"]

  # Replication factor.
  replication_factor = "3"

  # The number of nodes in the cluster, this cannot be lower than the replication factor.
  num_instances = "3"
}
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
