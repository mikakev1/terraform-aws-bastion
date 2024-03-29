# AWS ECR Terraform module

![alt text](_docs/diagram.png)

This module aims to create resilient bastions.

 This module creates for each bastion creates:

- An EC2 instance for the bastion with an auto scaling group

- A Network loadbalancer load balancer attached to the bastion

- many of security groups

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| auto\_scaling\_group\_subnets | List of subnet were the Auto Scalling Group will deploy the instances | list | n/a | yes |
| bastion\_host\_key\_pair | Select the key pair to use to launch the bastion host | string | n/a | yes |
| bucket\_name | Bucket name were the bastion will store the logs | string | n/a | yes |
| create\_dns\_record | Choose if you want to create a record name for the bastion (LB). If true 'hosted_zone_name' and 'bastion_record_name' are mandatory | string | n/a | yes |
| elb\_subnets | List of subnet were the ELB will be deployed | list | n/a | yes |
| environment | Environement | string | n/a | yes |
| is\_lb\_private | If TRUE the load balancer scheme will be "internal" else "internet-facing" | string | n/a | yes |
| region |  | string | n/a | yes |
| vpc\_id | VPC id were we'll deploy the bastion | string | n/a | yes |
| associate\_public\_ip\_address |  | string | `"true"` | no |
| bastion\_instance\_count |  | string | `"1"` | no |
| bastion\_launch\_configuration\_name | Bastion Launch configuration Name, will also be used for the ASG | string | `"lc"` | no |
| bastion\_record\_name | DNS record name to use for the bastion | string | `""` | no |
| bucket\_force\_destroy | The bucket and all objects should be destroyed when using true | string | `"false"` | no |
| bucket\_versioning | Enable bucket versioning or not | string | `"true"` | no |
| cidrs | List of CIDRs than can access to the bastion. Default : 0.0.0.0/0 | list | `<list>` | no |
| hosted\_zone\_name | Name of the hosted zone were we'll register the bastion DNS name | string | `""` | no |
| log\_auto\_clean | Enable or not the lifecycle | string | `"false"` | no |
| log\_expiry\_days | Number of days before logs expiration | string | `"90"` | no |
| log\_glacier\_days | Number of days before moving logs to Glacier | string | `"60"` | no |
| log\_standard\_ia\_days | Number of days before moving logs to IA Storage | string | `"30"` | no |
| private\_security\_group |  | string | `""` | no |
| private\_ssh\_port | Set the SSH port to use between the bastion and private instance | string | `"22"` | no |
| public\_security\_group |  | string | `""` | no |
| public\_ssh\_port | Set the SSH port to use from desktop to the bastion | string | `"22"` | no |
| tags | A mapping of tags to assign | map | `<map>` | no |

## Outputs

| Name | Description |
|------|-------------|
| bastion\_host\_security\_group |  |
| bucket\_name |  |
| elb\_ip |  |
| private\_instances\_security\_group |  |

## Usage

`````
module "sample"
  environment                = "stage"
  auto_scaling_group_subnets = ["subnet-09431a12fc6xxxxx","subnet-09431a12fc6yyyyy"]
  region                     = "eu-west-3"
  bastion_host_key_pair      = "my-keypair"
  bastion_instance_count     = "1"
  bucket_name                = "mybucket-bastion-logs"
  bucket_force_destroy       = true
  cidrs                      = "10.0.0.0/16"
  elb_subnets                = ["subnet-09431a12fc6wwwwww","subnet-09431a12fc6zzzzz"]
  is_lb_private              = "false"
  log_expiry_days            = "90"
  log_glacier_days           = "60"
  log_standard_ia_days       = "10"
  private_ssh_port           = "22"
  public_ssh_port            = "2"
  vpc_id                     = "vpc-08543dc6bb8b6xxxx"

  tags = {
    Name        = stage-bastion"
    Environment = "stage"
  }

`````