variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

variable "ssh_cidr" {
  description = "Public IP address allowed to use SSH"
  type        = string
}
