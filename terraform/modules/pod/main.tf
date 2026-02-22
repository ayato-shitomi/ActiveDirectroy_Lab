# Pod Module - EC2 Instances (DC, FILESRV, CLIENT)

locals {
  pod_name = "pod${var.pod_index}"
}

# Domain Controller
resource "aws_instance" "dc" {
  ami                    = var.windows_ami_id
  instance_type          = var.dc_instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  private_ip             = var.dc_private_ip

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/../../../scripts/dc/userdata.ps1", {
    admin_password  = var.dc_admin_password
    domain_name     = var.domain_name
    domain_netbios  = var.domain_netbios
    domain_password = var.domain_password
    dc_ip           = var.dc_private_ip
    computer_name   = "DC${var.pod_index}"
    user_password_nakanishi   = var.user_password_nakanishi
    user_password_hasegawa = var.user_password_hasegawa
    user_password_saitou   = var.user_password_saitou
  }))

  tags = {
    Name = "${var.name_prefix}-${local.pod_name}-dc"
    Role = "DomainController"
    Pod  = local.pod_name
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

# File Server
resource "aws_instance" "filesrv" {
  ami                    = var.windows_ami_id
  instance_type          = var.filesrv_instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  private_ip             = var.filesrv_private_ip

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/../../../scripts/filesrv/userdata.ps1", {
    admin_password  = var.filesrv_admin_password
    domain_name     = var.domain_name
    domain_netbios  = var.domain_netbios
    domain_password = var.domain_password
    dc_ip           = var.dc_private_ip
    computer_name   = "FILESRV${var.pod_index}"
  }))

  tags = {
    Name = "${var.name_prefix}-${local.pod_name}-filesrv"
    Role = "FileServer"
    Pod  = local.pod_name
  }

  depends_on = [aws_instance.dc]

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Client
resource "aws_instance" "client" {
  ami                    = var.windows_ami_id
  instance_type          = var.client_instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  private_ip             = var.client_private_ip

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/../../../scripts/client/userdata.ps1", {
    admin_password  = var.client_admin_password
    domain_name     = var.domain_name
    domain_netbios  = var.domain_netbios
    dc_ip           = var.dc_private_ip
    computer_name   = "CLIENT${var.pod_index}"
    nagata_password   = var.client_local_user_nagata_password
    saitou_password = var.user_password_saitou
  }))

  tags = {
    Name = "${var.name_prefix}-${local.pod_name}-client"
    Role = "Client"
    Pod  = local.pod_name
  }

  depends_on = [aws_instance.dc]

  lifecycle {
    ignore_changes = [user_data]
  }
}
