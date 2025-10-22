resource "aws_security_group" "bastion_sg" {
  name   = var.bastion_sg_name
  vpc_id = var.vpc_id

  # Allow all inbound traffic
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress (use variable for allowed CIDRs)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.bastion_sg_egress_cidr
  }

  tags = {
    Name = var.bastion_sg_name
  }
}

resource "aws_instance" "bastion" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true
  key_name                    = var.key_name

  user_data                   = file("${path.module}/user_data.sh")

  tags = {
    Name    = var.bastion_name
    Role    = var.bastion_role
    Cluster = var.bastion_cluster
  }
}
