# Managed by Level4 Iteration3.sh.
# Dynamic lookups keep terraform.tfvars limited to environment-specific inputs.

variable "aws_owner" {
  type        = string
  description = "Owner/environment identifier used to derive AWS resource names."

  validation {
    condition     = can(regex("^[A-Za-z0-9._+=,@-]{1,64}$", var.aws_owner))
    error_message = "aws_owner must contain 1-64 IAM-safe characters."
  }
}

variable "ec2_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type. Override with TF_VAR_ec2_type when required."
}

data "aws_ami" "iteration3_selected" {
  owners = ["amazon"]

  filter {
    name   = "image-id"
    values = [local.iteration3_selected_ami_id]
  }
}

data "aws_vpc" "iteration3_default" {
  default = true
}

data "aws_subnets" "iteration3_default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.iteration3_default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_security_groups" "iteration3_main" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.iteration3_default.id]
  }

  filter {
    name   = "group-name"
    values = [local.iteration3_main_sg_name]
  }
}

locals {
  iteration3_ec2_name        = format("devops.school.level3.%s", var.aws_owner)
  iteration3_selected_ami_id = "ami-0ef91fd8b3791aac0"
  iteration3_ami_id          = data.aws_ami.iteration3_selected.id
  iteration3_subnet_id       = sort(data.aws_subnets.iteration3_default.ids)[0]
  iteration3_keypair         = "petter-ec2-key"
  iteration3_main_sg_name    = "devops-school-level3"
  iteration3_main_sg_id      = one(data.aws_security_groups.iteration3_main.ids)
}
