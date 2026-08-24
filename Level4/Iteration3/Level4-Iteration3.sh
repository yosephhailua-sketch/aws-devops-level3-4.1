#!/usr/bin/env bash

# Level 4 – Iteration 3: dynamic Terraform lookups and minimal tfvars
#
# This script refactors an existing Level 3 Terraform root module so that
# account/environment values are derived from one identifier: aws_owner.
# It replaces the old var.* references without replacing complete resource
# files, creates a recoverable backup, validates the result, produces a saved
# Terraform plan, blocks destructive plans by default, and can optionally
# apply, test, commit, and push the change.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_NAME=$(basename -- "${BASH_SOURCE[0]}")

PROJECT_DIR=$PWD
OWNER_OVERRIDE=""
PROFILE_OVERRIDE=""
REGION_OVERRIDE=""
SSH_CIDR_OVERRIDE=""
AMI_ID_OVERRIDE=""
USE_LATEST_AMI=0
SECURITY_GROUP_NAME_OVERRIDE=""
SECURITY_GROUP_FORMAT='level3.%s'
KEY_NAME_OVERRIDE=""
KEY_NAME_FORMAT='devops.school.level3.%s'
INSTANCE_TYPE_DEFAULT='t3.micro'
EXPECTED_TEXT=""
URL_OVERRIDE=""
REMOTE_NAME='origin'
BRANCH_OVERRIDE=""
COMMIT_MESSAGE='level 3 - iteration 7 - dynamic lookups and minimal tfvars'

ASSUME_YES=0
CHECK_ONLY=0
DO_APPLY=0
ALLOW_DESTROY=0
SKIP_WEB_TEST=0
DO_COMMIT=0
DO_PUSH=0

OWNER=""
REGION=""
ACCOUNT_ID=""
CALLER_ARN=""
SSH_CIDR=""
AMI_ID=""
AMI_SOURCE=""
DEFAULT_VPC_ID=""
SECURITY_GROUP_NAME=""
SECURITY_GROUP_SOURCE=""
SECURITY_GROUP_IS_EXACT=0
KEY_NAME=""
KEY_NAME_SOURCE=""
KEY_NAME_IS_EXACT=0
KEYPAIR_DISABLED=0
NO_KEY_PAIR_REQUESTED=0
BACKUP_DIR=""
PLAN_FILE=""
MUTATION_STARTED=0
CONFIG_VERIFIED=0
INFRA_READY_FOR_TEST=0
BRANCH_NAME=""

USES_AMI=0
USES_SUBNET=0
USES_KEYPAIR=0
USES_MAIN_SG=0
USES_EC2_NAME=0
USES_SSH_CIDR=0

usage() {
  cat <<USAGE
Usage:
  ${SCRIPT_NAME} [options]

Run this script from the Terraform root module, or use --project-dir.

Core options:
  --project-dir PATH       Terraform root module. Default: current directory.
  --owner NAME             aws_owner value. Default: existing tfvars/AWS identity.
  --profile PROFILE        AWS CLI profile. Default: inherited AWS_PROFILE/default.
  --region REGION          AWS region. Default: environment/AWS config/eu-north-1.
  --instance-type TYPE     Default EC2 type. Default: t3.micro.
  --ssh-cidr CIDR          IPv4 CIDR allowed to use SSH. Default: preserve the
                           existing terraform.tfvars value.
  --ami-id AMI             Pin a specific existing AMI through a data lookup.
                           Default: preserve current tfvars/state AMI.
  --latest-ami             Use the latest AL2023 SSM AMI. This may replace EC2.
  --sg-name NAME           Exact existing security-group name. Overrides
                           automatic state discovery and --sg-format.
  --sg-format FORMAT       Security-group name with one %s for owner.
                           Fallback when state discovery finds no unique group.
                           Default: level3.%s
  --key-name NAME          Exact existing EC2 key-pair name. Overrides
                           automatic instance discovery and --key-format.
  --no-key-pair            Preserve an existing EC2 instance without a key pair.
  --key-format FORMAT      EC2 key-pair name with one %s for owner.
                           Fallback when discovery finds no unique instance.
                           Default: devops.school.level3.%s
  --check-only             Validate prerequisites without changing files.

Terraform actions:
  --apply                  Apply the exact saved plan after confirmation.
  --allow-destroy          Permit a plan containing delete/replace actions.
                           This never implies --apply.
  --yes                    Accept file refactor/apply confirmations.

Web verification:
  --expected-text TEXT     Require TEXT in the HTTP response.
  --url URL                Test this URL instead of Terraform output discovery.
  --skip-web-test          Do not run the HTTP test.

Git actions (all opt-in):
  --commit                 Commit the Terraform refactor.
  --push                   Commit and push the current branch.
  --remote NAME            Git remote. Default: origin.
  --branch NAME            Required current branch. Default: current branch.
  --commit-message TEXT    Git commit message.

Other:
  -h, --help               Show this help.

Recommended sequence:
  1. Check only:
     bash "${SCRIPT_NAME}" --project-dir ~/aws-devops-level3 --check-only

  2. Create/refactor files and inspect the plan (no apply):
     bash "${SCRIPT_NAME}" --project-dir ~/aws-devops-level3

  3. Apply after reviewing the previous plan:
     bash "${SCRIPT_NAME}" --project-dir ~/aws-devops-level3 --apply

  4. Commit and push only after a successful apply:
     bash "${SCRIPT_NAME}" --project-dir ~/aws-devops-level3 --commit
     bash "${SCRIPT_NAME}" --project-dir ~/aws-devops-level3 --push

Safety:
  * Existing Terraform resource files are patched, not blindly overwritten.
  * Every changed project file is backed up inside .level4-iteration3-backups/.
  * A failed refactor/validate/plan restores the pre-run files automatically.
  * Plans containing delete or replace actions are blocked by default.
  * Existing AMI is pinned by default; upgrades require --latest-ami.
  * Security-specific ssh_cidr stays local in ignored terraform.tfvars.
  * apply, commit, and push require explicit flags.
USAGE
}

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  if declare -F restore_backup >/dev/null 2>&1; then
    restore_backup
  fi
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

confirm() {
  local prompt=$1

  if (( ASSUME_YES == 1 )); then
    return 0
  fi

  [[ -t 0 ]] || die "Interactive confirmation is required. Re-run with --yes after reviewing the request."

  local answer
  read -r -p "${prompt} [y/N] " answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || die "Cancelled by user."
}

cleanup() {
  if [[ -n "$PLAN_FILE" && -f "$PLAN_FILE" ]]; then
    rm -f -- "$PLAN_FILE"
  fi
}

restore_backup() {
  (( MUTATION_STARTED == 1 )) || return 0
  (( CONFIG_VERIFIED == 0 )) || return 0
  [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]] || return 0

  warn "Restoring project files because refactor validation did not finish."

  local relative
  if [[ -f "$BACKUP_DIR/existing-files.txt" ]]; then
    while IFS= read -r relative; do
      [[ -n "$relative" ]] || continue
      if [[ -f "$BACKUP_DIR/files/$relative" ]]; then
        cp -- "$BACKUP_DIR/files/$relative" "$PROJECT_DIR/$relative"
      fi
    done <"$BACKUP_DIR/existing-files.txt"
  fi

  if [[ -f "$BACKUP_DIR/new-files.txt" ]]; then
    while IFS= read -r relative; do
      [[ -n "$relative" ]] || continue
      case "$relative" in
        iteration3.tf|terraform.tfvars|.gitignore)
          rm -f -- "$PROJECT_DIR/$relative"
          ;;
        *)
          warn "Refusing to remove unexpected path from backup manifest: $relative"
          ;;
      esac
    done <"$BACKUP_DIR/new-files.txt"
  fi

  warn "Original files restored. Backup kept at: $BACKUP_DIR"
}

on_error() {
  local rc=$?
  local line=${BASH_LINENO[0]:-unknown}
  local failed_command=${BASH_COMMAND:-unknown}
  failed_command=${failed_command%%$'\n'*}
  failed_command=${failed_command:0:160}
  restore_backup
  printf '[ERROR] Command failed on line %s (exit %s): %s\n' \
    "$line" "$rc" "$failed_command" >&2
  exit "$rc"
}

trap on_error ERR
trap cleanup EXIT

validate_owner() {
  local value=$1
  [[ "$value" =~ ^[A-Za-z0-9._+=,@-]{1,64}$ ]] \
    || die "Owner must be 1-64 IAM-safe characters: letters, digits, . _ + = , @ -"
}

validate_name_format() {
  local label=$1
  local value=$2
  local without_placeholder=${value//%s/}
  local after_first=${value/\%s/}

  [[ "$value" == *'%s'* ]] || die "$label must contain one %s placeholder."
  [[ "$after_first" != *'%s'* ]] || die "$label must contain exactly one %s placeholder."
  [[ "$without_placeholder" != *'%'* ]] || die "$label contains an unsupported % sequence: $value"
  [[ "$value" =~ ^[A-Za-z0-9._+=,@/%-]+$ ]] \
    || die "$label contains unsafe characters: $value"
}

validate_security_group_name() {
  local value=$1
  [[ "$value" =~ ^[A-Za-z0-9._+=,@/-]{1,255}$ ]] \
    || die "Security-group name contains unsupported characters: $value"
}

validate_key_pair_name() {
  local value=$1
  [[ "$value" =~ ^[A-Za-z0-9._+=,@/-]{1,255}$ ]] \
    || die "EC2 key-pair name contains unsupported characters: $value"
}

validate_ssh_cidr() {
  local value=$1
  if ! python3 - "$value" <<'PYTHON'
import ipaddress
import sys

try:
    network = ipaddress.ip_network(sys.argv[1], strict=True)
except ValueError:
    raise SystemExit(1)

raise SystemExit(0 if network.version == 4 else 1)
PYTHON
  then
    die "Invalid IPv4 SSH CIDR: $value"
  fi
}

validate_ami_id() {
  local value=$1
  [[ "$value" =~ ^ami-[0-9a-fA-F]{8,32}$ ]] \
    || die "Invalid AMI ID: $value"
}

extract_tfvars_string() {
  local file=$1
  local key=$2

  [[ -f "$file" ]] || return 0
  awk -v wanted="$key" '
    $1 == wanted && $2 == "=" {
      value = $0
      sub(/^[^=]*=[[:space:]]*"/, "", value)
      sub(/".*/, "", value)
      print value
      exit
    }
  ' "$file"
}

derive_owner_from_arn() {
  local arn=$1
  local candidate=""

  case "$arn" in
    arn:*:iam::*:user/*)
      candidate=${arn#*:user/}
      candidate=${candidate##*/}
      ;;
    arn:*:sts::*:assumed-role/*)
      candidate=${arn##*/}
      ;;
    arn:*:iam::*:role/*)
      candidate=${arn#*:role/}
      candidate=${candidate##*/}
      ;;
  esac

  printf '%s' "$candidate"
}

discover_managed_security_group() {
  local -a addresses=()
  local address state_text group_id group_json group_name

  mapfile -t addresses < <(
    cd "$PROJECT_DIR"
    terraform state list 2>/dev/null \
      | awk '
          /(^|\.)aws_security_group\./ && !/(^|\.)data\.aws_security_group\./ {
            print
          }
        '
  )

  (( ${#addresses[@]} == 1 )) || return 1
  address=${addresses[0]}

  state_text=$(cd "$PROJECT_DIR" && terraform state show -no-color "$address" 2>/dev/null) \
    || return 1
  group_id=$(awk '
    $1 == "id" && $2 == "=" {
      value = $3
      gsub(/"/, "", value)
      print value
      exit
    }
  ' <<<"$state_text")
  [[ "$group_id" =~ ^sg-[A-Za-z0-9]+$ ]] || return 1

  group_json=$(aws ec2 describe-security-groups --group-ids "$group_id" --output json 2>/dev/null) \
    || return 1
  group_name=$(jq -er '.SecurityGroups[0].GroupName | select(length > 0)' <<<"$group_json") \
    || return 1
  validate_security_group_name "$group_name"

  SECURITY_GROUP_NAME=$group_name
  SECURITY_GROUP_SOURCE="Terraform state: $address ($group_id)"
  SECURITY_GROUP_IS_EXACT=1
  return 0
}

resolve_security_group_id() {
  local group_id=$1
  local group_json group_name

  [[ "$group_id" =~ ^sg-[A-Za-z0-9]+$ ]] || return 1
  group_json=$(aws ec2 describe-security-groups --group-ids "$group_id" --output json 2>/dev/null) \
    || return 1
  group_name=$(jq -er '.SecurityGroups[0].GroupName | select(length > 0)' <<<"$group_json") \
    || return 1
  validate_security_group_name "$group_name"

  SECURITY_GROUP_NAME=$group_name
  SECURITY_GROUP_SOURCE="existing main_sg_id: $group_id"
  SECURITY_GROUP_IS_EXACT=1
  return 0
}

discover_managed_instance_key_pair() {
  local -a addresses=()
  local address state_text instance_id instance_json key_name

  mapfile -t addresses < <(
    cd "$PROJECT_DIR"
    terraform state list 2>/dev/null \
      | awk '
          /(^|\.)aws_instance\./ && !/(^|\.)data\.aws_instance\./ {
            print
          }
        '
  )

  (( ${#addresses[@]} == 1 )) || return 1
  address=${addresses[0]}

  state_text=$(cd "$PROJECT_DIR" && terraform state show -no-color "$address" 2>/dev/null) \
    || return 1
  instance_id=$(awk '
    $1 == "id" && $2 == "=" {
      value = $3
      gsub(/"/, "", value)
      print value
      exit
    }
  ' <<<"$state_text")
  [[ "$instance_id" =~ ^i-[A-Za-z0-9]+$ ]] || return 1

  instance_json=$(aws ec2 describe-instances --instance-ids "$instance_id" --output json 2>/dev/null) \
    || return 1
  key_name=$(jq -r '.Reservations[0].Instances[0].KeyName // empty' <<<"$instance_json") \
    || return 1

  if [[ -z "$key_name" || "$key_name" == "None" || "$key_name" == "null" ]]; then
    KEY_NAME=""
    KEY_NAME_SOURCE="Terraform state: $address ($instance_id) has no key pair"
    KEY_NAME_IS_EXACT=1
    KEYPAIR_DISABLED=1
    return 0
  fi

  validate_key_pair_name "$key_name"
  KEY_NAME=$key_name
  KEY_NAME_SOURCE="Terraform state: $address ($instance_id)"
  KEY_NAME_IS_EXACT=1
  KEYPAIR_DISABLED=0
  return 0
}

discover_managed_instance_ami() {
  local -a addresses=()
  local address state_text instance_id instance_json image_id

  mapfile -t addresses < <(
    cd "$PROJECT_DIR"
    terraform state list 2>/dev/null \
      | awk '
          /(^|\.)aws_instance\./ && !/(^|\.)data\.aws_instance\./ {
            print
          }
        '
  )

  (( ${#addresses[@]} == 1 )) || return 1
  address=${addresses[0]}
  state_text=$(cd "$PROJECT_DIR" && terraform state show -no-color "$address" 2>/dev/null) \
    || return 1
  instance_id=$(awk '
    $1 == "id" && $2 == "=" {
      value = $3
      gsub(/"/, "", value)
      print value
      exit
    }
  ' <<<"$state_text")
  [[ "$instance_id" =~ ^i-[A-Za-z0-9]+$ ]] || return 1

  instance_json=$(aws ec2 describe-instances --instance-ids "$instance_id" --output json 2>/dev/null) \
    || return 1
  image_id=$(jq -er '.Reservations[0].Instances[0].ImageId | select(length > 0)' <<<"$instance_json") \
    || return 1
  validate_ami_id "$image_id"

  AMI_ID=$image_id
  AMI_SOURCE="Terraform state: $address ($instance_id)"
  return 0
}

project_uses_reference() {
  local old_reference=$1
  local new_reference=$2
  local file

  for file in "$PROJECT_DIR"/*.tf; do
    [[ -f "$file" ]] || continue
    [[ $(basename -- "$file") == 'iteration3.tf' ]] && continue
    if grep -Eq "${old_reference}|${new_reference}" "$file"; then
      return 0
    fi
  done
  return 1
}

ensure_gitignore() {
  local destination="$PROJECT_DIR/.gitignore"
  local temporary
  temporary=$(mktemp "$PROJECT_DIR/.gitignore.tmp.XXXXXX")

  if [[ -f "$destination" ]]; then
    cp -- "$destination" "$temporary"
  fi

  local pattern
  local -a patterns=(
    '.terraform/'
    '*.tfstate'
    '*.tfstate.*'
    '*.tfplan'
    'tfplan'
    'terraform.tfvars'
    '.level4-iteration3-backups/'
    'crash.log'
    'crash.*.log'
  )

  for pattern in "${patterns[@]}"; do
    if ! grep -Fqx -- "$pattern" "$temporary" 2>/dev/null; then
      printf '%s\n' "$pattern" >>"$temporary"
    fi
  done

  chmod 0644 "$temporary"
  if [[ -f "$destination" ]] && cmp -s -- "$temporary" "$destination"; then
    rm -f -- "$temporary"
  else
    mv -- "$temporary" "$destination"
    log "Updated .gitignore"
  fi
}

backup_project_files() {
  local timestamp relative file
  timestamp=$(date -u +'%Y%m%dT%H%M%SZ')
  mkdir -p -- "$PROJECT_DIR/.level4-iteration3-backups"
  BACKUP_DIR=$(mktemp -d "$PROJECT_DIR/.level4-iteration3-backups/${timestamp}.XXXXXX")
  mkdir -p -- "$BACKUP_DIR/files"
  : >"$BACKUP_DIR/existing-files.txt"
  : >"$BACKUP_DIR/new-files.txt"

  for file in "$PROJECT_DIR"/*.tf "$PROJECT_DIR/terraform.tfvars" "$PROJECT_DIR/.gitignore"; do
    [[ -e "$file" ]] || continue
    relative=$(basename -- "$file")
    cp -- "$file" "$BACKUP_DIR/files/$relative"
    printf '%s\n' "$relative" >>"$BACKUP_DIR/existing-files.txt"
  done

  for relative in iteration3.tf terraform.tfvars .gitignore; do
    if [[ ! -e "$PROJECT_DIR/$relative" ]]; then
      printf '%s\n' "$relative" >>"$BACKUP_DIR/new-files.txt"
    fi
  done

  MUTATION_STARTED=1
  log "Recovery backup created: $BACKUP_DIR"
}

preflight_aws_resources() {
  local count

  if (( USES_AMI == 1 )); then
    if (( USE_LATEST_AMI == 1 )); then
      aws ssm get-parameter \
        --name '/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64' \
        --query 'Parameter.Value' \
        --output text >/dev/null \
        || die "Cannot read the Amazon Linux 2023 public SSM parameter in $REGION."
    else
      count=$(aws ec2 describe-images \
        --image-ids "$AMI_ID" \
        --owners amazon \
        --query 'length(Images)' \
        --output text)
      [[ "$count" =~ ^[0-9]+$ ]] || die "Could not verify pinned AMI $AMI_ID."
      (( count == 1 )) || die "Pinned AMI $AMI_ID was not found as an Amazon-owned image in $REGION."
    fi
  fi

  if (( USES_SUBNET == 1 || USES_MAIN_SG == 1 )); then
    DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
      --filters Name=is-default,Values=true \
      --query 'Vpcs[0].VpcId' \
      --output text)
    [[ "$DEFAULT_VPC_ID" =~ ^vpc-[a-zA-Z0-9]+$ ]] \
      || die "No default VPC was found in region $REGION."
  fi

  if (( USES_SUBNET == 1 )); then
    count=$(aws ec2 describe-subnets \
      --filters \
        "Name=vpc-id,Values=$DEFAULT_VPC_ID" \
        Name=default-for-az,Values=true \
      --query 'length(Subnets)' \
      --output text)
    [[ "$count" =~ ^[0-9]+$ ]] || die "Could not count default subnets."
    (( count > 0 )) || die "The default VPC has no default subnet in $REGION."
  fi

  if (( USES_MAIN_SG == 1 )); then
    count=$(aws ec2 describe-security-groups \
      --filters \
        "Name=vpc-id,Values=$DEFAULT_VPC_ID" \
        "Name=group-name,Values=$SECURITY_GROUP_NAME" \
      --query 'length(SecurityGroups)' \
      --output text)
    [[ "$count" =~ ^[0-9]+$ ]] || die "Could not count matching security groups."
    (( count == 1 )) \
      || die "Expected exactly one security group named '$SECURITY_GROUP_NAME' in $DEFAULT_VPC_ID; found $count. Use --sg-name for an exact existing name or --sg-format for an owner-based pattern."
  fi

  if (( USES_KEYPAIR == 1 && KEYPAIR_DISABLED == 0 )); then
    aws ec2 describe-key-pairs \
      --key-names "$KEY_NAME" \
      --query 'KeyPairs[0].KeyName' \
      --output text >/dev/null \
      || die "EC2 key pair '$KEY_NAME' does not exist in $REGION. Use --key-name for an exact existing name, --no-key-pair for an instance without one, or --key-format for an owner-based pattern."
  fi
}

write_dynamic_configuration() {
  local destination="$PROJECT_DIR/iteration3.tf"
  local temporary
  temporary=$(mktemp "$PROJECT_DIR/iteration3.tf.tmp.XXXXXX")

  {
    cat <<'HCL'
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
  default     = "INSTANCE_TYPE_PLACEHOLDER"
  description = "EC2 instance type. Override with TF_VAR_ec2_type when required."
}
HCL

    if (( USES_AMI == 1 )); then
      if (( USE_LATEST_AMI == 1 )); then
        cat <<'HCL'

data "aws_ssm_parameter" "iteration3_amazon_linux_ami_id" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}
HCL
      else
        cat <<'HCL'

data "aws_ami" "iteration3_selected" {
  owners = ["amazon"]

  filter {
    name   = "image-id"
    values = [local.iteration3_selected_ami_id]
  }
}
HCL
      fi
    fi

    if (( USES_SUBNET == 1 || USES_MAIN_SG == 1 )); then
      cat <<'HCL'

data "aws_vpc" "iteration3_default" {
  default = true
}
HCL
    fi

    if (( USES_SUBNET == 1 )); then
      cat <<'HCL'

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
HCL
    fi

    if (( USES_MAIN_SG == 1 )); then
      if (( SECURITY_GROUP_IS_EXACT == 1 )); then
        cat <<HCL

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
HCL
      else
        cat <<HCL

data "aws_security_groups" "iteration3_main" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.iteration3_default.id]
  }

  filter {
    name   = "group-name"
    values = [format("${SECURITY_GROUP_FORMAT}", var.aws_owner)]
  }
}
HCL
      fi
    fi

    cat <<'HCL'

locals {
HCL
    if (( USES_EC2_NAME == 1 )); then
      printf '  iteration3_ec2_name = format("devops.school.level3.%%s", var.aws_owner)\n'
    fi
    if (( USES_AMI == 1 )); then
      if (( USE_LATEST_AMI == 1 )); then
        printf '  iteration3_ami_id = data.aws_ssm_parameter.iteration3_amazon_linux_ami_id.value\n'
      else
        printf '  iteration3_selected_ami_id = "%s"\n' "$AMI_ID"
        printf '  iteration3_ami_id          = data.aws_ami.iteration3_selected.id\n'
      fi
    fi
    if (( USES_SUBNET == 1 )); then
      printf '  iteration3_subnet_id = sort(data.aws_subnets.iteration3_default.ids)[0]\n'
    fi
    if (( USES_KEYPAIR == 1 )); then
      if (( KEYPAIR_DISABLED == 1 )); then
        printf '  iteration3_keypair = null\n'
      elif (( KEY_NAME_IS_EXACT == 1 )); then
        printf '  iteration3_keypair = "%s"\n' "$KEY_NAME"
      else
        printf '  iteration3_keypair = format("%s", var.aws_owner)\n' "$KEY_NAME_FORMAT"
      fi
    fi
    if (( USES_MAIN_SG == 1 )); then
      if (( SECURITY_GROUP_IS_EXACT == 1 )); then
        printf '  iteration3_main_sg_name = "%s"\n' "$SECURITY_GROUP_NAME"
      fi
      printf '  iteration3_main_sg_id = one(data.aws_security_groups.iteration3_main.ids)\n'
    fi
    cat <<'HCL'
}
HCL
  } >"$temporary"

  sed -i "s/INSTANCE_TYPE_PLACEHOLDER/$INSTANCE_TYPE_DEFAULT/" "$temporary"
  chmod 0644 "$temporary"

  if [[ -f "$destination" ]] && cmp -s -- "$temporary" "$destination"; then
    rm -f -- "$temporary"
    log "Already correct: iteration3.tf"
  else
    mv -- "$temporary" "$destination"
    log "Wrote iteration3.tf"
  fi
}

refactor_existing_terraform() {
  PROJECT_DIR_FOR_REFACTOR=$PROJECT_DIR python3 <<'PYTHON'
import os
import pathlib
import re

root = pathlib.Path(os.environ["PROJECT_DIR_FOR_REFACTOR"])
generated = root / "iteration3.tf"

replacements = {
    "var.ami_id": "local.iteration3_ami_id",
    "var.subnet_id": "local.iteration3_subnet_id",
    "var.keypair": "local.iteration3_keypair",
    "var.main_sg_id": "local.iteration3_main_sg_id",
    "var.ec2_name": "local.iteration3_ec2_name",
}
managed_variables = set(replacements) | {"var.aws_owner", "var.ec2_type"}
managed_names = {item.split(".", 1)[1] for item in managed_variables}
preserved_required_names = {"ssh_cidr"}


def matching_brace(text: str, opening: int) -> int:
    depth = 0
    quote = None
    escaped = False
    line_comment = False
    block_comment = False
    i = opening
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if line_comment:
            if ch == "\n":
                line_comment = False
            i += 1
            continue
        if block_comment:
            if ch == "*" and nxt == "/":
                block_comment = False
                i += 2
            else:
                i += 1
            continue
        if quote:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                quote = None
            i += 1
            continue
        if ch == "#":
            line_comment = True
            i += 1
            continue
        if ch == "/" and nxt == "/":
            line_comment = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            block_comment = True
            i += 2
            continue
        if ch in ('"', "'"):
            quote = ch
            i += 1
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError("unbalanced Terraform block")


def variable_spans(text: str):
    pattern = re.compile(r'(?m)^[ \t]*variable[ \t]+"([^"\n]+)"[ \t]*\{')
    for match in pattern.finditer(text):
        opening = text.find("{", match.start(), match.end())
        closing = matching_brace(text, opening)
        end = closing + 1
        while end < len(text) and text[end] in " \t":
            end += 1
        if end < len(text) and text[end] == "\n":
            end += 1
        yield match.group(1), match.start(), end, text[opening + 1 : closing]


required_unknown = set()
for path in sorted(root.glob("*.tf")):
    if path == generated:
        continue
    text = path.read_text(encoding="utf-8")
    for name, _, _, body in variable_spans(text):
        if (
            name not in managed_names
            and name not in preserved_required_names
            and not re.search(r'(?m)^[ \t]*default[ \t]*=', body)
        ):
            required_unknown.add(name)

if required_unknown:
    names = ", ".join(sorted(required_unknown))
    raise SystemExit(
        "Cannot create minimal terraform.tfvars: these unrelated variables "
        f"have no default values: {names}"
    )

for path in sorted(root.glob("*.tf")):
    if path == generated:
        continue
    original = path.read_text(encoding="utf-8")
    text = original

    spans = [
        (start, end)
        for name, start, end, _ in variable_spans(text)
        if name in managed_names
    ]
    for start, end in reversed(spans):
        text = text[:start] + text[end:]

    for old, new in replacements.items():
        text = re.sub(rf"(?<![A-Za-z0-9_]){re.escape(old)}(?![A-Za-z0-9_])", new, text)

    text = re.sub(r"\n{3,}", "\n\n", text).strip() + "\n"
    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"[INFO] Refactored {path.name}")
PYTHON
}

write_minimal_tfvars() {
  local destination="$PROJECT_DIR/terraform.tfvars"
  local temporary
  temporary=$(mktemp "$PROJECT_DIR/terraform.tfvars.tmp.XXXXXX")
  printf 'aws_owner = "%s"\n' "$OWNER" >"$temporary"
  if (( USES_SSH_CIDR == 1 )); then
    printf 'ssh_cidr  = "%s"\n' "$SSH_CIDR" >>"$temporary"
  fi
  chmod 0600 "$temporary"

  if [[ -f "$destination" ]] && cmp -s -- "$temporary" "$destination"; then
    rm -f -- "$temporary"
    log "Already correct: terraform.tfvars"
  else
    mv -- "$temporary" "$destination"
    if (( USES_SSH_CIDR == 1 )); then
      log "Wrote minimal terraform.tfvars (aws_owner + ssh_cidr)"
    else
      log "Reduced terraform.tfvars to aws_owner"
    fi
  fi
}

show_changes() {
  local -a files=(.gitignore iteration3.tf main.tf variables.tf s3.tf .terraform.lock.hcl)
  if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$PROJECT_DIR" status --short -- "${files[@]}"
    git --no-pager -C "$PROJECT_DIR" diff -- "${files[@]}" ':!terraform.tfvars' || true
    if [[ -f "$PROJECT_DIR/iteration3.tf" ]] \
      && ! git -C "$PROJECT_DIR" ls-files --error-unmatch iteration3.tf >/dev/null 2>&1; then
      log "New managed file: iteration3.tf"
      sed -n '1,220p' "$PROJECT_DIR/iteration3.tf"
    fi
  else
    log "Project is not in Git; compare against backup: $BACKUP_DIR"
  fi
}

run_plan() {
  local rc delete_count replace_count
  PLAN_FILE=$(mktemp "${TMPDIR:-/tmp}/level4-iteration3.XXXXXX.tfplan")

  if (
    cd "$PROJECT_DIR"
    terraform plan -input=false -detailed-exitcode -out="$PLAN_FILE"
  ); then
    rc=0
  else
    rc=$?
  fi

  case "$rc" in
    0)
      log "Terraform reports: No changes."
      CONFIG_VERIFIED=1
      INFRA_READY_FOR_TEST=1
      return 0
      ;;
    2)
      ;;
    *)
      die "terraform plan failed with exit code $rc."
      ;;
  esac

  delete_count=$(terraform show -json "$PLAN_FILE" \
    | jq '[.resource_changes[]? | select(.change.actions | index("delete"))] | length')
  replace_count=$(terraform show -json "$PLAN_FILE" \
    | jq '[.resource_changes[]? | select((.change.actions | index("delete")) and (.change.actions | index("create")))] | length')

  [[ "$delete_count" =~ ^[0-9]+$ && "$replace_count" =~ ^[0-9]+$ ]] \
    || die "Could not inspect destructive actions in the Terraform plan."

  if (( delete_count > 0 && ALLOW_DESTROY == 0 )); then
    die "Plan contains $delete_count delete action(s), including $replace_count replacement(s). Files will be restored. Review manually or explicitly use --allow-destroy."
  fi

  if (( delete_count > 0 )); then
    warn "Plan contains $delete_count delete action(s), including $replace_count replacement(s)."
    confirm "Continue with this destructive plan?"
  fi

  CONFIG_VERIFIED=1

  if (( DO_APPLY == 0 )); then
    log "Plan contains changes, but --apply was not supplied. Infrastructure was not changed."
    log "Review the diff and rerun with --apply when ready."
    return 0
  fi

  confirm "Apply the exact saved Terraform plan shown above?"
  if (
    cd "$PROJECT_DIR"
    terraform apply -input=false "$PLAN_FILE"
  ); then
    :
  else
    rc=$?
    die "terraform apply failed with exit code $rc. Configuration is retained because the apply may have partially changed infrastructure."
  fi
  log "Saved Terraform plan applied successfully."

  rm -f -- "$PLAN_FILE"
  PLAN_FILE=""
  verify_no_changes
  INFRA_READY_FOR_TEST=1
}

verify_no_changes() {
  local rc verify_plan
  verify_plan=$(mktemp "${TMPDIR:-/tmp}/level4-iteration3-verify.XXXXXX.tfplan")

  if (
    cd "$PROJECT_DIR"
    terraform plan -input=false -detailed-exitcode -out="$verify_plan"
  ); then
    rc=0
  else
    rc=$?
  fi
  rm -f -- "$verify_plan"

  case "$rc" in
    0)
      log "Post-apply verification passed: No changes."
      ;;
    2)
      die "Terraform still reports changes after apply. Review the new plan."
      ;;
    *)
      die "Post-apply terraform plan failed with exit code $rc."
      ;;
  esac
}

discover_web_url() {
  local outputs value name
  outputs=$(cd "$PROJECT_DIR" && terraform output -json 2>/dev/null) || return 1

  for name in ec2_public_dns_name public_dns instance_public_dns web_public_dns public_ip instance_public_ip; do
    value=$(jq -r --arg name "$name" '.[$name].value // empty' <<<"$outputs")
    if [[ -n "$value" && "$value" != "null" ]]; then
      if [[ "$value" =~ ^https?:// ]]; then
        printf '%s' "$value"
      else
        printf 'http://%s/' "$value"
      fi
      return 0
    fi
  done
  return 1
}

run_web_test() {
  local url response="" attempt
  (( SKIP_WEB_TEST == 0 )) || {
    log "Web test skipped by request."
    return 0
  }

  (( INFRA_READY_FOR_TEST == 1 )) || {
    warn "Web test skipped because the planned Terraform changes have not been applied."
    return 0
  }

  url=$URL_OVERRIDE
  if [[ -z "$url" ]]; then
    url=$(discover_web_url) || {
      warn "No supported public DNS/IP Terraform output was found; web test skipped."
      return 0
    }
  fi

  log "Testing $url"
  for attempt in $(seq 1 12); do
    if response=$(curl --fail --silent --show-error --max-time 15 "$url" 2>/dev/null); then
      break
    fi
    if (( attempt == 12 )); then
      die "Web server did not return a successful HTTP response after 12 attempts."
    fi
    sleep 5
  done

  if [[ -n "$EXPECTED_TEXT" ]] && ! grep -Fq -- "$EXPECTED_TEXT" <<<"$response"; then
    die "Web server responded, but expected text '$EXPECTED_TEXT' was not found."
  fi

  if [[ -n "$EXPECTED_TEXT" ]]; then
    log "Web test passed and found '$EXPECTED_TEXT'."
  else
    log "Web test passed with a successful HTTP response."
  fi
}

prepare_git_context() {
  local current_branch
  git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "$PROJECT_DIR is not inside a Git repository."

  current_branch=$(git -C "$PROJECT_DIR" branch --show-current)
  [[ -n "$current_branch" ]] || die "Git is in detached HEAD state."
  BRANCH_NAME=${BRANCH_OVERRIDE:-$current_branch}
  [[ "$current_branch" == "$BRANCH_NAME" ]] \
    || die "Current branch is '$current_branch', expected '$BRANCH_NAME'."

  if (( DO_PUSH == 1 )); then
    git -C "$PROJECT_DIR" remote get-url "$REMOTE_NAME" >/dev/null 2>&1 \
      || die "Git remote '$REMOTE_NAME' does not exist."
  fi
}

commit_and_push() {
  local -a files=(iteration3.tf main.tf variables.tf s3.tf .gitignore)
  [[ -f "$PROJECT_DIR/.terraform.lock.hcl" ]] && files+=('.terraform.lock.hcl')

  local -a existing_files=()
  local file
  for file in "${files[@]}"; do
    [[ -e "$PROJECT_DIR/$file" ]] && existing_files+=("$file")
  done

  git -C "$PROJECT_DIR" add -- "${existing_files[@]}"

  if git -C "$PROJECT_DIR" diff --cached --quiet; then
    log "No Terraform/Git changes need a new commit."
  else
    git -C "$PROJECT_DIR" commit -m "$COMMIT_MESSAGE"
    log "Created Git commit on branch $BRANCH_NAME."
  fi

  if (( DO_PUSH == 1 )); then
    git -C "$PROJECT_DIR" push --set-upstream "$REMOTE_NAME" "$BRANCH_NAME"
    log "Pushed branch $BRANCH_NAME to $REMOTE_NAME."
  fi
}

while (( $# > 0 )); do
  case "$1" in
    --project-dir)
      [[ $# -ge 2 ]] || die "--project-dir requires a path."
      PROJECT_DIR=$2
      shift 2
      ;;
    --owner)
      [[ $# -ge 2 ]] || die "--owner requires a value."
      OWNER_OVERRIDE=$2
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || die "--profile requires a value."
      PROFILE_OVERRIDE=$2
      shift 2
      ;;
    --region)
      [[ $# -ge 2 ]] || die "--region requires a value."
      REGION_OVERRIDE=$2
      shift 2
      ;;
    --instance-type)
      [[ $# -ge 2 ]] || die "--instance-type requires a value."
      INSTANCE_TYPE_DEFAULT=$2
      shift 2
      ;;
    --ssh-cidr)
      [[ $# -ge 2 ]] || die "--ssh-cidr requires a value."
      SSH_CIDR_OVERRIDE=$2
      shift 2
      ;;
    --ami-id)
      [[ $# -ge 2 ]] || die "--ami-id requires a value."
      AMI_ID_OVERRIDE=$2
      shift 2
      ;;
    --latest-ami)
      USE_LATEST_AMI=1
      shift
      ;;
    --sg-name)
      [[ $# -ge 2 ]] || die "--sg-name requires a value."
      SECURITY_GROUP_NAME_OVERRIDE=$2
      shift 2
      ;;
    --sg-format)
      [[ $# -ge 2 ]] || die "--sg-format requires a value."
      SECURITY_GROUP_FORMAT=$2
      shift 2
      ;;
    --key-name)
      [[ $# -ge 2 ]] || die "--key-name requires a value."
      KEY_NAME_OVERRIDE=$2
      shift 2
      ;;
    --no-key-pair)
      NO_KEY_PAIR_REQUESTED=1
      shift
      ;;
    --key-format)
      [[ $# -ge 2 ]] || die "--key-format requires a value."
      KEY_NAME_FORMAT=$2
      shift 2
      ;;
    --expected-text)
      [[ $# -ge 2 ]] || die "--expected-text requires a value."
      EXPECTED_TEXT=$2
      shift 2
      ;;
    --url)
      [[ $# -ge 2 ]] || die "--url requires a value."
      URL_OVERRIDE=$2
      shift 2
      ;;
    --remote)
      [[ $# -ge 2 ]] || die "--remote requires a value."
      REMOTE_NAME=$2
      shift 2
      ;;
    --branch)
      [[ $# -ge 2 ]] || die "--branch requires a value."
      BRANCH_OVERRIDE=$2
      shift 2
      ;;
    --commit-message)
      [[ $# -ge 2 ]] || die "--commit-message requires a value."
      COMMIT_MESSAGE=$2
      shift 2
      ;;
    --check-only)
      CHECK_ONLY=1
      shift
      ;;
    --apply)
      DO_APPLY=1
      shift
      ;;
    --allow-destroy)
      ALLOW_DESTROY=1
      shift
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    --skip-web-test)
      SKIP_WEB_TEST=1
      shift
      ;;
    --commit)
      DO_COMMIT=1
      shift
      ;;
    --push)
      DO_PUSH=1
      DO_COMMIT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1. Use --help for usage."
      ;;
  esac
done

for command_name in aws terraform jq python3 awk sed grep cmp cp mv chmod mktemp date seq; do
  require_command "$command_name"
done
(( SKIP_WEB_TEST == 1 )) || require_command curl
if (( DO_COMMIT == 1 || DO_PUSH == 1 )); then
  require_command git
fi

[[ -d "$PROJECT_DIR" ]] || die "Project directory does not exist: $PROJECT_DIR"
PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd -P)
compgen -G "$PROJECT_DIR/*.tf" >/dev/null \
  || die "No Terraform .tf files found in $PROJECT_DIR"

validate_name_format '--sg-format' "$SECURITY_GROUP_FORMAT"
validate_name_format '--key-format' "$KEY_NAME_FORMAT"
if [[ -n "$SSH_CIDR_OVERRIDE" ]]; then
  validate_ssh_cidr "$SSH_CIDR_OVERRIDE"
fi
if [[ -n "$AMI_ID_OVERRIDE" ]]; then
  validate_ami_id "$AMI_ID_OVERRIDE"
fi
if [[ -n "$AMI_ID_OVERRIDE" && "$USE_LATEST_AMI" == 1 ]]; then
  die "--ami-id and --latest-ami cannot be used together."
fi
if [[ -n "$SECURITY_GROUP_NAME_OVERRIDE" ]]; then
  validate_security_group_name "$SECURITY_GROUP_NAME_OVERRIDE"
fi
if [[ -n "$KEY_NAME_OVERRIDE" ]]; then
  validate_key_pair_name "$KEY_NAME_OVERRIDE"
fi
if [[ -n "$KEY_NAME_OVERRIDE" && "$NO_KEY_PAIR_REQUESTED" == 1 ]]; then
  die "--key-name and --no-key-pair cannot be used together."
fi
[[ "$INSTANCE_TYPE_DEFAULT" =~ ^[a-z0-9][a-z0-9.]*$ ]] \
  || die "Invalid EC2 instance type: $INSTANCE_TYPE_DEFAULT"

if [[ -n "$PROFILE_OVERRIDE" ]]; then
  export AWS_PROFILE=$PROFILE_OVERRIDE
fi

REGION=${REGION_OVERRIDE:-${AWS_REGION:-${AWS_DEFAULT_REGION:-}}}
if [[ -z "$REGION" ]]; then
  REGION=$(aws configure get region 2>/dev/null || true)
fi
REGION=${REGION:-eu-north-1}
export AWS_REGION=$REGION
export AWS_DEFAULT_REGION=$REGION

caller_json=$(aws sts get-caller-identity --output json) \
  || die "AWS authentication failed. Renew your login and verify aws sts get-caller-identity."
ACCOUNT_ID=$(jq -er '.Account | select(test("^[0-9]{12}$"))' <<<"$caller_json") \
  || die "AWS STS did not return a valid 12-digit account ID."
CALLER_ARN=$(jq -er '.Arn | select(length > 0)' <<<"$caller_json") \
  || die "AWS STS did not return a caller ARN."

existing_owner=$(extract_tfvars_string "$PROJECT_DIR/terraform.tfvars" aws_owner)
existing_ssh_cidr=$(extract_tfvars_string "$PROJECT_DIR/terraform.tfvars" ssh_cidr)
existing_ami_id=$(extract_tfvars_string "$PROJECT_DIR/terraform.tfvars" ami_id)
existing_pinned_ami_id=$(extract_tfvars_string "$PROJECT_DIR/iteration3.tf" iteration3_selected_ami_id)
existing_main_sg_id=$(extract_tfvars_string "$PROJECT_DIR/terraform.tfvars" main_sg_id)
existing_main_sg_name=$(extract_tfvars_string "$PROJECT_DIR/iteration3.tf" iteration3_main_sg_name)
derived_owner=$(derive_owner_from_arn "$CALLER_ARN")
OWNER=${OWNER_OVERRIDE:-${existing_owner:-$derived_owner}}
[[ -n "$OWNER" ]] \
  || die "Could not derive aws_owner from AWS identity. Pass --owner explicitly."
validate_owner "$OWNER"

project_uses_reference 'var\.ami_id' 'local\.iteration3_ami_id' && USES_AMI=1
project_uses_reference 'var\.subnet_id' 'local\.iteration3_subnet_id' && USES_SUBNET=1
project_uses_reference 'var\.keypair' 'local\.iteration3_keypair' && USES_KEYPAIR=1
project_uses_reference 'var\.main_sg_id' 'local\.iteration3_main_sg_id' && USES_MAIN_SG=1
project_uses_reference 'var\.ec2_name' 'local\.iteration3_ec2_name' && USES_EC2_NAME=1
project_uses_reference 'var\.ssh_cidr' 'local\.iteration3_ssh_cidr' && USES_SSH_CIDR=1

if (( USES_SSH_CIDR == 1 )); then
  SSH_CIDR=${SSH_CIDR_OVERRIDE:-$existing_ssh_cidr}
  [[ -n "$SSH_CIDR" ]] \
    || die "ssh_cidr is required by the project but no value was found. Pass --ssh-cidr with a narrow IPv4 CIDR such as your-public-ip/32."
  validate_ssh_cidr "$SSH_CIDR"
fi

if (( USES_AMI == 1 )); then
  if (( USE_LATEST_AMI == 1 )); then
    AMI_ID=""
    AMI_SOURCE='latest AL2023 SSM parameter (--latest-ami)'
  elif [[ -n "$AMI_ID_OVERRIDE" ]]; then
    AMI_ID=$AMI_ID_OVERRIDE
    AMI_SOURCE='--ami-id'
  elif [[ -n "$existing_ami_id" ]]; then
    AMI_ID=$existing_ami_id
    AMI_SOURCE='existing terraform.tfvars ami_id'
  elif [[ -n "$existing_pinned_ami_id" ]]; then
    AMI_ID=$existing_pinned_ami_id
    AMI_SOURCE='existing iteration3.tf pin'
  elif discover_managed_instance_ami; then
    :
  else
    die "Could not preserve the current EC2 AMI. Pass --ami-id explicitly or use --latest-ami after reviewing replacement risk."
  fi

  if (( USE_LATEST_AMI == 0 )); then
    validate_ami_id "$AMI_ID"
  fi
fi

if (( USES_MAIN_SG == 1 )); then
  if [[ -n "$SECURITY_GROUP_NAME_OVERRIDE" ]]; then
    SECURITY_GROUP_NAME=$SECURITY_GROUP_NAME_OVERRIDE
    SECURITY_GROUP_SOURCE='--sg-name'
    SECURITY_GROUP_IS_EXACT=1
  elif [[ -n "$existing_main_sg_id" ]] && resolve_security_group_id "$existing_main_sg_id"; then
    :
  elif [[ -n "$existing_main_sg_name" ]]; then
    SECURITY_GROUP_NAME=$existing_main_sg_name
    SECURITY_GROUP_SOURCE='existing iteration3.tf pin'
    SECURITY_GROUP_IS_EXACT=1
  elif [[ -n "$SECURITY_GROUP_FORMAT" ]]; then
    printf -v SECURITY_GROUP_NAME "$SECURITY_GROUP_FORMAT" "$OWNER"
    SECURITY_GROUP_SOURCE='owner-based fallback format'
    SECURITY_GROUP_IS_EXACT=0
  elif discover_managed_security_group; then
    :
  else
    die "Could not resolve main_sg_id. Pass --sg-name with the existing external security-group name."
  fi
fi

if (( USES_KEYPAIR == 1 )); then
  if (( NO_KEY_PAIR_REQUESTED == 1 )); then
    KEY_NAME=""
    KEY_NAME_SOURCE='--no-key-pair'
    KEY_NAME_IS_EXACT=1
    KEYPAIR_DISABLED=1
  elif [[ -n "$KEY_NAME_OVERRIDE" ]]; then
    KEY_NAME=$KEY_NAME_OVERRIDE
    KEY_NAME_SOURCE='--key-name'
    KEY_NAME_IS_EXACT=1
    KEYPAIR_DISABLED=0
  elif discover_managed_instance_key_pair; then
    :
  else
    printf -v KEY_NAME "$KEY_NAME_FORMAT" "$OWNER"
    KEY_NAME_SOURCE='owner-based fallback format'
    KEY_NAME_IS_EXACT=0
    KEYPAIR_DISABLED=0
  fi
fi

log "AWS identity      : $CALLER_ARN"
log "AWS account       : $ACCOUNT_ID"
log "AWS profile       : ${AWS_PROFILE:-default}"
log "AWS region        : $REGION"
log "Terraform project : $PROJECT_DIR"
log "aws_owner         : $OWNER"
(( USES_SSH_CIDR == 0 )) || log "SSH CIDR          : $SSH_CIDR (preserved local input)"
if (( USES_AMI == 1 )); then
  if (( USE_LATEST_AMI == 1 )); then
    log "AMI selection     : latest AL2023 (replacement may be required)"
  else
    log "AMI selection     : $AMI_ID (preserved)"
  fi
  log "AMI resolution    : $AMI_SOURCE"
fi
if (( USES_MAIN_SG == 1 )); then
  log "Security group    : $SECURITY_GROUP_NAME"
  log "SG resolution     : $SECURITY_GROUP_SOURCE"
fi
if (( USES_KEYPAIR == 1 )); then
  if (( KEYPAIR_DISABLED == 1 )); then
    log "EC2 key pair      : <none>"
  else
    log "EC2 key pair      : $KEY_NAME"
  fi
  log "Key resolution    : $KEY_NAME_SOURCE"
fi

terraform version | sed -n '1,2p'
preflight_aws_resources

if (( DO_COMMIT == 1 || DO_PUSH == 1 )); then
  prepare_git_context
  log "Git branch        : $BRANCH_NAME"
fi

if (( CHECK_ONLY == 1 )); then
  log "Preflight checks passed. No files or infrastructure were changed."
  exit 0
fi

confirm "Back up and refactor Terraform files in $PROJECT_DIR?"
backup_project_files
ensure_gitignore
write_dynamic_configuration
refactor_existing_terraform
write_minimal_tfvars

if (
  cd "$PROJECT_DIR"
  terraform fmt
  terraform init -input=false
  terraform validate
); then
  :
else
  terraform_setup_rc=$?
  die "Terraform format/init/validate failed with exit code $terraform_setup_rc."
fi

show_changes
run_plan
run_web_test

if (( DO_COMMIT == 1 )); then
  commit_and_push
fi

log "Iteration 3 workflow completed successfully."
log "Recovery backup: $BACKUP_DIR"
if (( DO_APPLY == 0 )); then
  log "No apply was requested. Use --apply only after reviewing the plan."
fi
if (( DO_COMMIT == 0 )); then
  log "Git was not changed. Review git status before committing."
fi
