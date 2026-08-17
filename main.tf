data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  selected_ami_id = var.ami_id != null ? var.ami_id : data.aws_ami.amazon_linux.id

  security_group_ids = var.main_sg_id == null ? [
    aws_security_group.web.id
    ] : [
    aws_security_group.web.id,
    var.main_sg_id
  ]
}

resource "aws_security_group" "web" {
  name_prefix = "aws-devops-level3-"
  description = "SSH from my IP and HTTP from the internet"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from my current public IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  ingress {
    description = "Public HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "aws-devops-level3-sg"
    Project = "AWS DevOps Level 3"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "web" {
  ami                         = local.selected_ami_id
  instance_type               = var.ec2_type
  subnet_id                   = var.subnet_id
  key_name                    = var.keypair
  vpc_security_group_ids      = local.security_group_ids
  associate_public_ip_address = true

  user_data                   = file("${path.module}/user-data.web.sh")
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 10
    encrypted   = true
  }

  tags = {
    Name    = var.ec2_name
    Project = "AWS DevOps Level 3"
  }
}
