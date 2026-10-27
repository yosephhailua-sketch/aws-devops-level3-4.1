data "aws_ssm_parameter" "amazon_linux_ami_id" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_region" "current" {}

data "aws_subnet" "default" {
  vpc_id = data.aws_vpc.default.id

  filter {
    name   = "availability-zone"
    values = [format("%sa", data.aws_region.current.region)]
  }
}

data "aws_security_groups" "main" {
  filter {
    name   = "group-name"
    values = ["apl-web-sg"]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

locals {
  ec2_name   = format("devops-school-level3.%s", var.aws_owner)
  ami_id     = nonsensitive(data.aws_ssm_parameter.amazon_linux_ami_id.value)
  subnet_id  = data.aws_subnet.default.id
  keypair    = "ec2kp"
  main_sg_id = data.aws_security_groups.main.ids[0]
}

variable "aws_owner" {
  type        = string
  description = "The individual that is taking care of this infrastructure"
}

variable "ec2_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type to construct"
}
