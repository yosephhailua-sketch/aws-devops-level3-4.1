#!/usr/bin/env bash
set -euo pipefail

echo "Refreshing Terraform backend configuration..."

MY_USER=$(aws sts get-caller-identity --query Arn --output text | awk -F'/' '{print $NF}')
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)

if [[ -z "$MY_USER" || -z "$AWS_ACCOUNT" || -z "$AWS_REGION" ]]; then
  echo "ERROR: Could not determine AWS user, account, or region." >&2
  exit 1
fi

cat > terraform.tfvars <<EOV
aws_owner = "$MY_USER"
EOV

cat > backend.tf <<EOT
terraform {
  backend "s3" {
    bucket       = "${MY_USER}-${AWS_ACCOUNT}-terraform-state"
    key          = "level4/iteration1/terraform.tfstate"
    region       = "${AWS_REGION}"
    encrypt      = true
    use_lockfile = true
  }
}
EOT

echo "Generated terraform.tfvars and backend.tf."
echo "Bucket: ${MY_USER}-${AWS_ACCOUNT}-terraform-state"
echo "State key: level4/iteration1/terraform.tfstate"
echo "Region: ${AWS_REGION}"
