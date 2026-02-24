# AWS AD Lab Environment - Variable Definitions

# AWS Configuration
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-northeast-1"
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.100.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet (Bastion)"
  type        = string
  default     = "10.100.0.0/24"
}

# Pod Configuration
variable "pod_count" {
  description = "Number of AD Lab pods to deploy"
  type        = number
  default     = 1

  validation {
    condition     = var.pod_count >= 1 && var.pod_count <= 10
    error_message = "Pod count must be between 1 and 10."
  }
}

# EC2 Configuration
variable "bastion_instance_type" {
  description = "Instance type for Bastion host"
  type        = string
  default     = "t3.small"
}

variable "bastion_password" {
  description = "Password for Bastion ubuntu user (SSH login)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.bastion_password) >= 8
    error_message = "Bastion password must be at least 8 characters."
  }
}

variable "dc_instance_type" {
  description = "Instance type for Domain Controller"
  type        = string
  default     = "t3.medium"
}

variable "filesrv_instance_type" {
  description = "Instance type for File Server"
  type        = string
  default     = "t3.medium"
}

variable "client_instance_type" {
  description = "Instance type for Client machine"
  type        = string
  default     = "t3.medium"
}

# Security Configuration
variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access to Bastion"
  type        = string
  default     = "0.0.0.0/0"
}

# Windows/AD Configuration
variable "admin_password" {
  description = "Default password for local Administrator account (used if individual passwords not set)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.admin_password) >= 8
    error_message = "Admin password must be at least 8 characters."
  }
}

variable "dc_admin_password" {
  description = "Password for DC local Administrator (defaults to admin_password if not set)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "filesrv_admin_password" {
  description = "Password for FILESRV local Administrator (defaults to admin_password if not set)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "client_admin_password" {
  description = "Password for CLIENT local Administrator (defaults to admin_password if not set)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "client_local_user_nagata_password" {
  description = "Password for CLIENT local user nagata"
  type        = string
  sensitive   = true
  default     = "P@ssw0rd!"
}

variable "domain_name" {
  description = "Active Directory domain name"
  type        = string
  default     = "lab.local"
}

variable "domain_netbios" {
  description = "NetBIOS name for the domain"
  type        = string
  default     = "LAB"
}

variable "domain_password" {
  description = "Password for domain Administrator and DSRM"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.domain_password) >= 8
    error_message = "Domain password must be at least 8 characters."
  }
}

# AD User Passwords
variable "svc_backup_password" {
  description = "Password for service account svc_backup"
  type        = string
  sensitive   = true
  default     = "P@ssw0rd123!"
}

variable "user_password_hasegawa" {
  description = "Password for AD user hasegawa"
  type        = string
  sensitive   = true
  default     = "P@ssw0rd!"
}

variable "user_password_saitou" {
  description = "Password for AD user saitou"
  type        = string
  sensitive   = true
  default     = "P@ssw0rd!"
}

# CTF Flags Configuration
variable "flag_client_admin" {
  description = "Flag for CLIENT Administrator desktop"
  type        = string
  default     = "THIS_IS_FLAG"
}

variable "flag_filesrv_admin" {
  description = "Flag for FILESRV Administrator desktop"
  type        = string
  default     = "THIS_IS_FLAG"
}

variable "flag_filesrv_hasegawa" {
  description = "Flag for FILESRV hasegawa desktop"
  type        = string
  default     = "THIS_IS_FLAG"
}

variable "flag_filesrv_saitou" {
  description = "Flag for FILESRV saitou desktop"
  type        = string
  default     = "THIS_IS_FLAG"
}

variable "flag_dc_admin" {
  description = "Flag for DC Administrator desktop"
  type        = string
  default     = "THIS_IS_FLAG"
}
