# Pod Module - Variable Definitions

variable "pod_index" {
  description = "Index number of this pod"
  type        = number
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the pod"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for pod instances"
  type        = string
}

variable "windows_ami_id" {
  description = "Windows Server 2022 AMI ID"
  type        = string
}

variable "dc_instance_type" {
  description = "Instance type for Domain Controller"
  type        = string
}

variable "filesrv_instance_type" {
  description = "Instance type for File Server"
  type        = string
}

variable "client_instance_type" {
  description = "Instance type for Client"
  type        = string
}

variable "dc_admin_password" {
  description = "DC local Administrator password"
  type        = string
  sensitive   = true
}

variable "filesrv_admin_password" {
  description = "FILESRV local Administrator password"
  type        = string
  sensitive   = true
}

variable "client_admin_password" {
  description = "CLIENT local Administrator password"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Active Directory domain name"
  type        = string
}

variable "domain_netbios" {
  description = "NetBIOS name for the domain"
  type        = string
}

variable "domain_password" {
  description = "Domain Administrator and DSRM password"
  type        = string
  sensitive   = true
}

variable "dc_private_ip" {
  description = "Private IP address for Domain Controller"
  type        = string
}

variable "filesrv_private_ip" {
  description = "Private IP address for File Server"
  type        = string
}

variable "client_private_ip" {
  description = "Private IP address for Client"
  type        = string
}

variable "user_password_nakanishi" {
  description = "Password for AD user nakanishi"
  type        = string
  sensitive   = true
}

variable "user_password_hasegawa" {
  description = "Password for AD user hasegawa"
  type        = string
  sensitive   = true
}

variable "user_password_saitou" {
  description = "Password for AD user saitou"
  type        = string
  sensitive   = true
}

variable "client_local_user_nagata_password" {
  description = "Password for CLIENT local user nagata"
  type        = string
  sensitive   = true
}
