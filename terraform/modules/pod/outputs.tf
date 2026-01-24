# Pod Module - Outputs

output "dc_instance_id" {
  description = "Instance ID of the Domain Controller"
  value       = aws_instance.dc.id
}

output "dc_private_ip" {
  description = "Private IP of the Domain Controller"
  value       = aws_instance.dc.private_ip
}

output "filesrv_instance_id" {
  description = "Instance ID of the File Server"
  value       = aws_instance.filesrv.id
}

output "filesrv_private_ip" {
  description = "Private IP of the File Server"
  value       = aws_instance.filesrv.private_ip
}

output "client_instance_id" {
  description = "Instance ID of the Client"
  value       = aws_instance.client.id
}

output "client_private_ip" {
  description = "Private IP of the Client"
  value       = aws_instance.client.private_ip
}

output "pod_index" {
  description = "Index of this pod"
  value       = var.pod_index
}
