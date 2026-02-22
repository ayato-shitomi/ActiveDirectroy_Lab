# AWS AD Lab Environment - Outputs

output "bastion_public_ip" {
  description = "Public IP address of the Bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to Bastion"
  value       = "ssh ubuntu@${aws_instance.bastion.public_ip}"
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "pod_info" {
  description = "Information about each pod"
  value = {
    for idx, pod in module.pod : "pod${idx + 1}" => {
      dc = {
        instance_id = pod.dc_instance_id
        private_ip  = pod.dc_private_ip
        rdp_tunnel  = "ssh -L 3389:${pod.dc_private_ip}:3389 ubuntu@${aws_instance.bastion.public_ip}"
      }
      filesrv = {
        instance_id = pod.filesrv_instance_id
        private_ip  = pod.filesrv_private_ip
        rdp_tunnel  = "ssh -L 3390:${pod.filesrv_private_ip}:3389 ubuntu@${aws_instance.bastion.public_ip}"
      }
      client = {
        instance_id = pod.client_instance_id
        private_ip  = pod.client_private_ip
        rdp_tunnel  = "ssh -L 3391:${pod.client_private_ip}:3389 ubuntu@${aws_instance.bastion.public_ip}"
      }
    }
  }
}

output "connection_instructions" {
  description = "Instructions for connecting to the lab environment"
  value       = <<-EOT

    ==================== AD Lab Connection Instructions ====================

    1. SSH to Bastion:
       ssh ubuntu@${aws_instance.bastion.public_ip}
       Password: <bastion_password>

    2. For RDP access, create SSH tunnel through Bastion:

       ssh -L 3389:${module.pod[0].dc_private_ip}:3389 ubuntu@${aws_instance.bastion.public_ip} # Pod 1 DC
       ssh -L 3390:${module.pod[0].filesrv_private_ip}:3389 ubuntu@${aws_instance.bastion.public_ip} # Pod 1 FILESRV
       ssh -L 3391:${module.pod[0].client_private_ip}:3389 ubuntu@${aws_instance.bastion.public_ip} # Pod 1 CLIENT

    3. Connect via RDP to localhost:3389 (or 3390, 3391)

    4. Login credentials:

       [Bastion SSH]
       - User: ubuntu / <bastion_password>

       [Local Administrator]
       - DC:      Administrator / <dc_admin_password or admin_password>
       - FILESRV: Administrator / <filesrv_admin_password or admin_password>
       - CLIENT:  Administrator / <client_admin_password or admin_password>

       [CLIENT Local User - Standard User (No Admin)]
       - nagata / <client_local_user_nagata_password> (default: P@ssw0rd!)

       [Domain Administrator]
       - LAB\\Administrator / <domain_password>

       [Domain Users]
       - LAB\\nakanishi / <user_password_nakanishi> (default: P@ssw0rd!)
       - LAB\\hasegawa / <user_password_hasegawa> (default: P@ssw0rd!)
       - LAB\\saitou / <user_password_saitou> (default: P@ssw0rd!)

    5. Test file shares:
       \\\\FILESRV${length(module.pod) > 0 ? "1" : ""}\\Share
       \\\\FILESRV${length(module.pod) > 0 ? "1" : ""}\\Public

    =========================================================================
  EOT
}
