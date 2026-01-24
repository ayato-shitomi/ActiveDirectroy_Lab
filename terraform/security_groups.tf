# AWS AD Lab Environment - Security Groups

# Bastion Security Group
resource "aws_security_group" "bastion" {
  name        = "${local.name_prefix}-sg-bastion"
  description = "Security group for Bastion host"
  vpc_id      = aws_vpc.main.id

  # SSH from allowed CIDR
  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg-bastion"
  }
}

# Pod Security Group
resource "aws_security_group" "pod" {
  name        = "${local.name_prefix}-sg-pod"
  description = "Security group for AD Lab Pod instances"
  vpc_id      = aws_vpc.main.id

  # All traffic within the security group (Pod internal communication)
  ingress {
    description = "All traffic within Pod"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # RDP from Bastion
  ingress {
    description     = "RDP from Bastion"
    from_port       = 3389
    to_port         = 3389
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # WinRM HTTP from Bastion
  ingress {
    description     = "WinRM HTTP from Bastion"
    from_port       = 5985
    to_port         = 5985
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # WinRM HTTPS from Bastion
  ingress {
    description     = "WinRM HTTPS from Bastion"
    from_port       = 5986
    to_port         = 5986
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # ICMP from Bastion (for ping)
  ingress {
    description     = "ICMP from Bastion"
    from_port       = -1
    to_port         = -1
    protocol        = "icmp"
    security_groups = [aws_security_group.bastion.id]
  }

  # All outbound traffic (for Windows Update, etc.)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg-pod"
  }
}
