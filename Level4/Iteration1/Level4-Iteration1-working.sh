#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)
cd "$PROJECT_DIR"
REQUIRED_COMMANDS=(aws awk curl terraform)

for command_name in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "ERROR: Required command is missing: $command_name" >&2
    exit 1
  fi
done

REQUIRED_FILES=(main.tf variables.tf user-data.web.sh)

for required_file in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$required_file" ]; then
    echo "ERROR: Required project file is missing: $required_file" >&2
    exit 1
  fi
done


require_value() {
  local value_name="$1"
  local value="$2"

  if [ -z "$value" ] || [ "$value" = "None" ] || [ "$value" = "null" ]; then
    echo "ERROR: AWS did not return a valid value for $value_name." >&2
    exit 1
  fi
}

###########################################################
# Local working-copy configuration
###########################################################
# GitHub publication is intentionally excluded during the rebuild.

###########################################################
# Level 4 Iteration 1: safe local rebuild
###########################################################
# Repository cloning, branch creation and push are intentionally excluded.
# REVIEW: mkdir ~/aws-devops-level4-iteration1
# REVIEW: cd ~/aws-devops-level4-iteration1
# REVIEW: git clone git@github.com:Nation-devapl/aws-devops-level4-iteration1.git
# REVIEW: cd aws-devops/src/level3
# (replace this with your real first name and last name)
# REVIEW: git checkout -b <yourfirst>.<yourlastname>
# REVIEW: git config --global push.autoSetupRemote true
# REVIEW: git push

###########################################################
# Re-run terraform with some improvements
###########################################################

# - get back all important varaibles
MY_USER=$(aws sts get-caller-identity --query Arn --output text | awk -F/ '{print $NF}')
MY_KEYNAME="petter-ec2-key"
MY_SSH="$HOME/.ssh/petter-ec2-key.pem"
MY_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=devops-school-level3" --query "SecurityGroups[0].GroupId" --output text)
MY_VPC=$(aws ec2 describe-security-groups --group-ids "$MY_SG" --query "SecurityGroups[0].VpcId" --output text)
MY_SUBNET=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${MY_VPC}" "Name=state,Values=available" --query "sort_by(Subnets,&AvailabilityZone)[0].SubnetId" --output text)
MY_AMI=$(aws ssm get-parameter --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64" --query "Parameter.Value" --output text)

require_value "MY_USER" "$MY_USER"
require_value "MY_SG" "$MY_SG"
require_value "MY_VPC" "$MY_VPC"
require_value "MY_SUBNET" "$MY_SUBNET"
require_value "MY_AMI" "$MY_AMI"

if [ ! -r "$MY_SSH" ]; then
  echo "ERROR: SSH private key is not readable: $MY_SSH" >&2
  exit 1
fi

aws ec2 describe-key-pairs --key-names "$MY_KEYNAME" >/dev/null

SUBNET_VPC=$(aws ec2 describe-subnets --subnet-ids "$MY_SUBNET" --query "Subnets[0].VpcId" --output text)

if [ "$SUBNET_VPC" != "$MY_VPC" ]; then
  echo "ERROR: Subnet and security group belong to different VPCs." >&2
  exit 1
fi

AMI_STATE=$(aws ec2 describe-images --image-ids "$MY_AMI" --query "Images[0].State" --output text)

if [ "$AMI_STATE" != "available" ]; then
  echo "ERROR: Selected AMI is not available: $MY_AMI" >&2
  exit 1
fi


if [ "${VALIDATE_ONLY:-0}" = "1" ]; then
  echo "Validation completed successfully."
  printf 'AWS user: %s\n' "$MY_USER"
  printf 'Security group: %s\n' "$MY_SG"
  printf 'Security-group VPC: %s\n' "$MY_VPC"
  printf 'Subnet: %s\n' "$MY_SUBNET"
  printf 'Subnet VPC: %s\n' "$SUBNET_VPC"
  printf 'AMI: %s\n' "$MY_AMI"
  printf 'AMI state: %s\n' "$AMI_STATE"
  printf 'Key pair: %s\n' "$MY_KEYNAME"
  exit 0
fi

if [ -e tfplan ]; then
  echo "ERROR: tfplan already exists. Review, archive or remove it before creating a new plan." >&2
  exit 1
fi

MY_PUBLIC_IP=$(curl -fsS https://checkip.amazonaws.com | tr -d '\r\n')

if ! [[ "$MY_PUBLIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "ERROR: Could not determine a valid public IPv4 address." >&2
  exit 1
fi

if [ -f terraform.tfvars ] && [ ! -f terraform.tfvars.before-level4 ]; then
  cp -p terraform.tfvars terraform.tfvars.before-level4
fi

cat <<EOF > terraform.tfvars
ami_id = "${MY_AMI}"
subnet_id = "${MY_SUBNET}"
main_sg_id = "${MY_SG}"
ec2_type = "t3.micro"
ec2_name = "devops-school-level3.${MY_USER}"
keypair = "${MY_KEYNAME}"
ssh_cidr = "${MY_PUBLIC_IP}/32"
EOF
terraform fmt terraform.tfvars >/dev/null

# - do the init
terraform init -input=false

terraform fmt -check
terraform validate

# - re-build using new user-data instructions
terraform plan -input=false -out=tfplan

# The script stops after creating the reviewable Terraform plan.
# Review with: terraform show -no-color tfplan
# Apply manually only after review: terraform apply "tfplan"
# Post-apply SSH and HTTP verification must be run separately.
# Terraform destroy is intentionally excluded.
