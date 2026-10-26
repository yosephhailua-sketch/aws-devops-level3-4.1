output "instance_id" {
  value = aws_instance.web.id
}

output "public_ip" {
  value = aws_instance.web.public_ip
}

output "ec2_public_dns_name" {
  value = aws_instance.web.public_dns
}

output "website_url" {
  value = "http://${aws_instance.web.public_dns}"
}
