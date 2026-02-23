# AWS AD Lab Environment - Main Configuration
# Provider and backend configuration

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "AD-Lab"
      Environment = "Training"
      ManagedBy   = "Terraform"
    }
  }
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_prefix = "ad-lab-${random_id.suffix.hex}"

  # Use individual passwords if set, otherwise fall back to admin_password
  dc_admin_password      = var.dc_admin_password != "" ? var.dc_admin_password : var.admin_password
  filesrv_admin_password = var.filesrv_admin_password != "" ? var.filesrv_admin_password : var.admin_password
  client_admin_password  = var.client_admin_password != "" ? var.client_admin_password : var.admin_password
}

# Pod modules
module "pod" {
  source   = "./modules/pod"
  count    = var.pod_count

  pod_index        = count.index + 1
  name_prefix      = local.name_prefix
  vpc_id           = aws_vpc.main.id
  subnet_id        = aws_subnet.private[count.index].id
  security_group_id = aws_security_group.pod.id

  dc_instance_type = var.dc_instance_type
  filesrv_instance_type = var.filesrv_instance_type
  client_instance_type  = var.client_instance_type

  windows_ami_id   = data.aws_ami.windows_2022.id

  dc_admin_password      = local.dc_admin_password
  filesrv_admin_password = local.filesrv_admin_password
  client_admin_password  = local.client_admin_password

  domain_name      = var.domain_name
  domain_netbios   = var.domain_netbios
  domain_password  = var.domain_password

  user_password_nakanishi   = var.user_password_nakanishi
  user_password_hasegawa = var.user_password_hasegawa
  user_password_saitou   = var.user_password_saitou

  client_local_user_nagata_password = var.client_local_user_nagata_password

  dc_private_ip      = cidrhost(aws_subnet.private[count.index].cidr_block, 10)
  filesrv_private_ip = cidrhost(aws_subnet.private[count.index].cidr_block, 20)
  client_private_ip  = cidrhost(aws_subnet.private[count.index].cidr_block, 30)

  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name
}
