#!/usr/bin/env bash
set -Eeuo pipefail

###########################################################
# Level 4 iteration 2: shared state management (S3 backend)
#
# WSL example:
#   bash /mnt/c/Users/Pette/aws-devops-level3/Level4/Iteration2/Level4-Iteration2.sh
###########################################################

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

resolve_existing_dir() {
  local candidate

  for candidate in "$@"; do
    [[ -n "$candidate" && -d "$candidate" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done

  return 1
}

DEFAULT_PROJECT_DIR="$(resolve_existing_dir \
  "${PROJECT_DIR:-}" \
  "$HOME/aws-devops-level3-iteration5" \
  "/mnt/c/Users/Pette/aws-devops-level3-iteration5" \
  || true)"
DEFAULT_PROJECT_DIR="${DEFAULT_PROJECT_DIR:-$HOME/aws-devops-level3-iteration5}"

DEFAULT_VERIFY_DIR="$(resolve_existing_dir \
  "${VERIFY_DIR:-}" \
  "$HOME/aws-devops-level3-iteration6" \
  "/mnt/c/Users/Pette/aws-devops-level3-iteration6" \
  || true)"
DEFAULT_VERIFY_DIR="${DEFAULT_VERIFY_DIR:-$HOME/aws-devops-level3-iteration6}"

PROJECT_DIR="${PROJECT_DIR:-$DEFAULT_PROJECT_DIR}"
VERIFY_DIR="${VERIFY_DIR:-$DEFAULT_VERIFY_DIR}"
REPO_URL="${REPO_URL:-https://github.com/Nation-devapl/aws-devops-level3-iteration5.git}"
GIT_BRANCH="${GIT_BRANCH:-Petter.Wastesson}"
AWS_REGION="${AWS_REGION:-eu-north-1}"
VERIFY_MARKER="${VERIFY_MARKER:-Hello Me!}"
MY_SSH="${MY_SSH:-$HOME/.ssh/id_rsa_level3}"

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'ERROR: Required command is missing: %s\n' "$command_name" >&2
    exit 1
  fi
}

require_value() {
  local value_name="$1"
  local value="$2"

  if [[ -z "$value" || "$value" == "None" || "$value" == "null" ]]; then
    printf 'ERROR: AWS did not return a valid value for %s.\n' "$value_name" >&2
    exit 1
  fi
}

verify_website() {
  local ec2_dns="$1"
  local attempt http_body

  for attempt in $(seq 1 12); do
    if http_body="$(curl --fail --silent --show-error --location \
      --connect-timeout 5 --max-time 15 "http://${ec2_dns}/" 2>&1)"; then
      if grep -Fq "$VERIFY_MARKER" <<< "$http_body"; then
        printf 'YES\n'
        return 0
      fi
      printf 'HTTP attempt %d returned content without the expected marker.\n' \
        "$attempt" >&2
    else
      printf 'HTTP attempt %d failed: %s\n' "$attempt" "$http_body" >&2
    fi
    sleep 5
  done

  return 1
}

collect_aws_context() {
  export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"

  MY_USER="$(aws sts get-caller-identity --query Arn --output text | awk -F/ '{print $NF}')"
  MY_KEYNAME="devops.school.level3.${MY_USER}"
  MY_SG="$(aws ec2 describe-security-groups \
    --group-names "level3.${MY_USER}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)"
  MY_SUBNET="$(aws ec2 describe-subnets \
    --query 'Subnets[*].SubnetId' \
    --output text | awk '{print $1}')"
  MY_AMI="$(aws ssm get-parameter \
    --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64 \
    --query Parameter.Value \
    --output text)"

  require_value "MY_USER" "$MY_USER"
  require_value "MY_SG" "$MY_SG"
  require_value "MY_SUBNET" "$MY_SUBNET"
  require_value "MY_AMI" "$MY_AMI"
}

write_tfvars() {
  cat > terraform.tfvars <<EOF
aws_owner = "${MY_USER}"
ami_id = "${MY_AMI}"
subnet_id = "${MY_SUBNET}"
main_sg_id = "${MY_SG}"
ec2_type = "t3.micro"
ec2_name = "devops-school-level3.${MY_USER}"
keypair = "${MY_KEYNAME}"
EOF
}

ensure_s3_tf() {
  if [[ -f s3.tf ]]; then
    return 0
  fi

  cat > s3.tf <<EOF
resource "aws_s3_bucket" "terraform-state" {
  bucket = "${MY_USER}-apl-devops-terraform-state"

  tags = {
    Team        = "APL"
    ManagedBy   = "terraform"
    Environment = var.ec2_name
  }
}

resource "aws_s3_bucket_versioning" "devops-terraform-state" {
  bucket = aws_s3_bucket.terraform-state.id

  versioning_configuration {
    status = "Enabled"
  }
}
EOF
}

write_backend_tf() {
  cat > backend.tf <<EOF
terraform {
  backend "s3" {
    bucket       = "${MY_USER}-apl-devops-terraform-state"
    key          = "devops.school"
    region       = "${AWS_REGION}"
    encrypt      = true
    use_lockfile = true
  }
}
EOF
}

ensure_repo() {
  if [[ ! -d "$PROJECT_DIR/.git" ]]; then
    printf 'Cloning %s into %s\n' "$REPO_URL" "$PROJECT_DIR"
    git clone "$REPO_URL" "$PROJECT_DIR"
  fi

  cd "$PROJECT_DIR"

  if git show-ref --verify --quiet "refs/heads/${GIT_BRANCH}"; then
    git checkout "$GIT_BRANCH"
  elif git show-ref --verify --quiet "refs/remotes/origin/${GIT_BRANCH}"; then
    git checkout -B "$GIT_BRANCH" "origin/${GIT_BRANCH}"
  else
    git checkout -B "$GIT_BRANCH"
  fi
}

phase_create_state_backend() {
  printf '\n=== Phase 1: create S3 state bucket and migrate local state ===\n'

  ensure_repo
  collect_aws_context
  write_tfvars
  ensure_s3_tf

  terraform init -input=false
  terraform plan -out=tfplan
  terraform apply "tfplan"

  write_backend_tf
  terraform init -migrate-state -input=false

  MY_EC2="$(terraform output -raw ec2_public_dns_name)"
  require_value "MY_EC2" "$MY_EC2"

  if verify_website "$MY_EC2"; then
    printf 'Deploy verification exit code: 0\n'
  else
    printf 'Deploy verification exit code: 1\n' >&2
    exit 1
  fi
}

phase_commit_and_push() {
  printf '\n=== Phase 2: commit shared-state files to branch %s ===\n' "$GIT_BRANCH"

  cd "$PROJECT_DIR"
  git add s3.tf
  git add -f backend.tf

  if git diff --cached --quiet; then
    printf 'No staged changes to commit.\n'
  else
    git commit -m "level 4 - iteration 2 - shared state"
    git push -u origin "$GIT_BRANCH"
  fi
}

phase_verify_fresh_clone() {
  printf '\n=== Phase 3: verify shared state from a fresh clone ===\n'

  rm -rf "$VERIFY_DIR"
  mkdir -p "$VERIFY_DIR"
  git clone "$REPO_URL" "$VERIFY_DIR/aws-devops-level3-iteration5"
  cd "$VERIFY_DIR/aws-devops-level3-iteration5"
  git checkout "$GIT_BRANCH"

  collect_aws_context
  write_tfvars

  terraform init -input=false
  terraform apply -auto-approve

  MY_EC2="$(terraform output -raw ec2_public_dns_name)"
  require_value "MY_EC2" "$MY_EC2"

  if verify_website "$MY_EC2"; then
    printf 'Fresh-clone verification exit code: 0\n'
  else
    printf 'Fresh-clone verification exit code: 1\n' >&2
    exit 1
  fi
}

main() {
  require_command aws
  require_command terraform
  require_command curl
  require_command git
  require_command awk

  case "${1:-all}" in
    create)
      phase_create_state_backend
      ;;
    commit)
      phase_commit_and_push
      ;;
    verify)
      phase_verify_fresh_clone
      ;;
    all)
      phase_create_state_backend
      phase_commit_and_push
      phase_verify_fresh_clone
      ;;
    *)
      printf 'Usage: %s [create|commit|verify|all]\n' "$0" >&2
      exit 1
      ;;
  esac
}

main "$@"
