resource "aws_s3_bucket" "devops_terraform_state" {
  bucket = format("%s-%s-apl-devops-terraform-state", var.aws_owner, data.aws_caller_identity.current.account_id)

  tags = {
    Team        = "APL"
    ManagedBy   = "terraform"
    Environment = local.ec2_name
  }
}

resource "aws_s3_bucket_versioning" "devops_terraform_state" {
  bucket = aws_s3_bucket.devops_terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_caller_identity" "current" {}
