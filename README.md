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
  ssh_keypair = "SSH_KEYPAIR_NAME_HERE"
  ssh_private_key = "SSH_PRIVATE_KEY_PATH_HERE"

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

**NOTE:** If you have a custom security group, you would need to add the `${var.custom_security_group_id}` variable in `main.tf`, so that the `aws_instance` looks as follows:

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
`Note:- To make any changes in the created cluster you will need the terraform state files. So don't delete state files of Terraform.`

## Test 

### Configurations

#### Prerequisites

- [Terraform **(~> 0.12.5)**](https://www.terraform.io/downloads.html)
- [Golang **(~> 1.12.10)**](https://golang.org/dl/)


#### Environment setup

* Sign Up for AWS.
* Configure your AWS credentials using one of the supported methods for AWS CLI tools, such as setting the AWS_ACCESS_KEY_ID and 
  AWS_SECRET_ACCESS_KEY environment variables.
* Install `dep` dependency management tool for Go.
    ```sh
    $ curl https://raw.githubusercontent.com/golang/dep/master/install.sh | sh
    ```  
* Change your working directory to the `test` folder.
* Run `dep` command to get required modules
    ```sh
    $ dep ensure
    ```

#### Run test

Then simply run it in the local shell:

```sh
$ go test -v -timeout 20m  yugabyte_test.go
```
* Note that go has a default test timeout of 10 minutes. With infrastructure testing, your tests will surpass the 10 minutes very easily. To extend the timeout, you can pass in the -timeout option, which takes a go duration string (e.g 10m for 10 minutes or 1h for 1 hour). In the above command, we use the -timeout option to override to a 90 minute timeout.
* When you hit the timeout, Go automatically exits the test, skipping all cleanup routines. This is problematic for infrastructure testing because it will skip your deferred infrastructure cleanup steps (i.e terraform destroy), leaving behind the infrastructure that was spun up. So it is important to use a longer timeout every time you run the tests.

