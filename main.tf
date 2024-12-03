provider "aws" {
  region = local.region
}
data "aws_availability_zones" "available" {}
locals {
  region = "us-west-2"
  name   = "ex-${basename(path.cwd)}"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Example    = local.name
    GithubRepo = "terraform-aws-vpc"
    GithubOrg  = "terraform-aws-modules"
  }
}

terraform {
  required_providers {
    hcp = {
      source = "hashicorp/hcp"
    }
  }
}

provider "hcp" {
 project_id = "a5f6afce-da16-4428-b96e-7e25b662db8f"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"
  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  public_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k+4)]

  tags = local.tags
}
resource "hcp_hvn" "us_west_2" {
  region         = "us-west-2"
  hvn_id         = "us-west-2"
  cloud_provider = "aws"

  # The CIDR block value must end between /16 and /25
  cidr_block = "172.25.20.0/22" # 1,024 addresses
}

resource "hcp_hvn" "us_east_1" {
  region         = "us-east-1"
  hvn_id         = "us-east-1"
  cloud_provider = "aws"

  # The CIDR block value must end between /16 and /25
  cidr_block = "172.25.24.0/22" # 1,024 addresses
}

resource "hcp_hvn_peering_connection" "us_east_1_to_us_west_2" {
  hvn_1 = hcp_hvn.us_east_1.self_link
  hvn_2 = hcp_hvn.us_west_2.self_link
}

resource "hcp_vault_cluster" "us_east_1_plus" {
  cluster_id                 = "aws-us-east-1-plus"
  hvn_id                     = hcp_hvn.us_east_1.hvn_id
  public_endpoint            = false
  tier                       = "plus_small"

  timeouts {}
}

resource "hcp_vault_cluster" "us_west_2_plus" {
  cluster_id                 = "aws-us-west-2-plus"
  hvn_id                     = hcp_hvn.us_west_2.hvn_id
  public_endpoint            = true
  tier                       = "plus_small"

  # replication
  primary_link = hcp_vault_cluster.us_east_1_plus.self_link

  timeouts {}
}

module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  associate_public_ip_address = "true"
  name = "single-instance"
  instance_type          = "t3.micro"
  key_name               = "dgreeninger-hcp-vault"
  monitoring             = true
  vpc_security_group_ids = [ module.vpc.default_security_group_id ]
  subnet_id              = module.vpc.public_subnets[0]
  user_data = "sudo yum install -y yum-utils; sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo; sudo yum -y install vault nginx"
  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
resource "aws_security_group_rule" "inbound" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id =  module.vpc.default_security_group_id 
}
# module "vpc-endpoints" {
#   source  = "figurate/vpc-endpoints/aws"
#   version = "1.0.0"
#   # insert the 2 required variables here
#   vpc = "vpc-0b6f4f069b0ea3e71"
#   aws_region = "us-east-1"
# }

# module "alb" {
#   source  = "terraform-aws-modules/alb/aws"
#   version = "~> 8.0"
# 
#   name = "vault-alb"
# 
#   load_balancer_type = "application"
# 
#   vpc_id  = module.vpc.default_vpc_id
#   subnets            = module.vpc.public_subnets
#   security_groups    = [ module.vpc.default_security_group_id ]
#   target_groups = [
#     {
#       name = "hcp-vault"
#       backend_protocol = "HTTPS"
#       backend_port     = 443
#     }
#   ]
# 
#   https_listeners = [
#     {
#       port               = 443
#       protocol           = "HTTPS"
#       certificate_arn    = "arn:aws:acm:us-east-1:694347674047:certificate/a3f7b082-3692-4326-a0de-3d304e6734ae"
#       target_group_index = 0
#     }
#   ]
# 
#   http_tcp_listeners = [
#     {
#       port               = 80
#       protocol           = "HTTP"
#       target_group_index = 0
#     }
#   ]
# 
#   tags = {
#     Environment = "Test"
#   }
# }
