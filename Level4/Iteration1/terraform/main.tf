resource "aws_instance" "web" {
  ami                         = local.ami_id
  instance_type               = var.ec2_type
  subnet_id                   = local.subnet_id
  key_name                    = local.keypair
  vpc_security_group_ids      = [local.main_sg_id]
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
    Name    = local.ec2_name
    Project = "AWS DevOps Level 3"
  }
}
