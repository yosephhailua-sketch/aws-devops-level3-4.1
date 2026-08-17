resource "aws_instance" "devops-school-level3" {
  ami             = var.ami_id
  instance_type   = var.ec2_type
    subnet_id                  = var.subnet_id
  associate_public_ip_address = true
  key_name                   = var.keypair

  vpc_security_group_ids = [var.main_sg_id]

  user_data = file("user-data.web.sh")
  user_data_replace_on_change = true

  tags = {
    Name = var.ec2_name
  }
}
output "ec2_public_dns_name" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_instance.devops-school-level3.public_dns
}
