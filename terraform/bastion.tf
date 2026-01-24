# AWS AD Lab Environment - Bastion Host

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.bastion_instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bastion.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/../scripts/bastion/setup.sh", {
    pod_count = var.pod_count
  }))

  tags = {
    Name = "${local.name_prefix}-bastion"
    Role = "Bastion"
  }
}
