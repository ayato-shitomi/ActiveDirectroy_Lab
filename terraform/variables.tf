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
variable "key_name" {
  description = "Name of the EC2 key pair for SSH/RDP access"
  type        = string
}

variable "bastion_instance_type" {
  description = "Instance type for Bastion host"
  type        = string
  default     = "t3.small"
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
  description = "Password for local Administrator account"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.admin_password) >= 8
    error_message = "Admin password must be at least 8 characters."
  }
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
variable "user_password_tanaka" {
  description = "Password for AD user tanaka"
  type        = string
  sensitive   = true
  default     = "P@ssw0rd!"
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
