variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

variable "ami_id" {
  description = "Optional AMI ID; the newest Amazon Linux 2023 AMI is used when null"
  type        = string
  default     = null
}

variable "ec2_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "Optional subnet ID; AWS selects a default subnet when null"
  type        = string
  default     = null
}

variable "keypair" {
  description = "Existing AWS EC2 key pair"
  type        = string
  default     = "petter-ec2-key"
}

variable "main_sg_id" {
  description = "Optional additional security group ID"
  type        = string
  default     = null
}

variable "ec2_name" {
  description = "Name of the EC2 instance"
  type        = string
  default     = "aws-devops-level3-web"
}

variable "ssh_cidr" {
  description = "Public IP address allowed to use SSH"
  type        = string
}
