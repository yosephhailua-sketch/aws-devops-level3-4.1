#!/usr/bin/env bash
############################################################
# Terraform prerequisites inherited from iteration 1
# Required Terraform variables:
#   ami_id, ec2_type, subnet_id, keypair, main_sg_id, ec2_name
# Required AWS context:
#   Authenticated AWS provider and an explicit AWS region
# Required AWS resources:
#   AMI, subnet, key pair and security group in the selected
#   account and region. The security group must allow TCP 22/80.
############################################################
set -Eeuo pipefail

###########################################################
# Terraform iteration 2: terraform + user-data(config mgmt)
###########################################################

PROJECT_DIR="${PROJECT_DIR:-$HOME/aws-devops-level3}"

if [[ ! -d "$PROJECT_DIR" ]]; then
  printf 'ERROR: Projektmappen finns inte: %s\n' "$PROJECT_DIR" >&2
  exit 1
fi

cd "$PROJECT_DIR"

BACKUP_DIR="$PROJECT_DIR/DMC-backups/$(date -u +'%Y%m%dT%H%M%SZ')-$$"
mkdir -p "$BACKUP_DIR"

backup_if_exists() {
  local target="$1"

  if [[ -f "$target" ]]; then
    cp -- "$target" "$BACKUP_DIR/$(basename "$target")"
  fi
}

USER_DATA_TMP=""
MAIN_TF_TMP=""

cleanup_temp_files() {
  [[ -z "${USER_DATA_TMP:-}" ]] || rm -f -- "$USER_DATA_TMP"
  [[ -z "${MAIN_TF_TMP:-}" ]] || rm -f -- "$MAIN_TF_TMP"
}
bash -n "$USER_DATA_TMP"
mv -- "$USER_DATA_TMP" "user-data.web.sh"
USER_DATA_TMP=""

trap cleanup_temp_files EXIT

# - create user data script
backup_if_exists "user-data.web.sh"

USER_DATA_TMP="$(mktemp "$PROJECT_DIR/.user-data.web.sh.XXXXXX")"

cat > "$USER_DATA_TMP" <<'EOF'
#!/bin/bash
###########################################################
# Perform configuration management
###########################################################
# - detect Amazon Linux version
if [[ ! -r /etc/os-release ]]; then
  printf 'ERROR: /etc/os-release kunde inte läsas.\n' >&2
  exit 1
fi

. /etc/os-release

if [[ "${ID:-}" != "amzn" ]]; then
  printf 'ERROR: Operativsystemet stöds inte: %s\n' "${ID:-unknown}" >&2
  exit 1
fi

# - upgrade os
yum -y update && yum -y upgrade

# - install Nginx and Git
case "${VERSION_ID:-}" in
  2023*)
    dnf -y install nginx git
    ;;
  2)
    amazon-linux-extras enable nginx1
    yum clean metadata
    yum -y install nginx git
    ;;
  *)
    printf 'ERROR: Amazon Linux-versionen stöds inte: %s\n' \
      "${VERSION_ID:-unknown}" >&2
    exit 1
    ;;
esac

# - enable and start Nginx
systemctl enable --now nginx

# - verify Nginx
if ! systemctl is-active --quiet nginx; then
  printf 'ERROR: Nginx is not active after startup.\n' >&2
  exit 1
fi

# - verify Git
if ! git --version; then
  printf 'ERROR: Git installation could not be verified.\n' >&2
  exit 1
fi

# - return to normal user mode
# exit
EOF

# - change main.tf to include user-data
backup_if_exists "main.tf"

# - preserve the current Terraform configuration before replacing it
MAIN_TF_BACKUP=""

if [[ -f "main.tf" ]]; then
  MAIN_TF_BACKUP="$(mktemp "$PROJECT_DIR/main.tf.before-iteration2.XXXXXX.bak")"
  cp -p -- "main.tf" "$MAIN_TF_BACKUP"
  printf 'Backup of main.tf created: %s\n' "$MAIN_TF_BACKUP"
fi

MAIN_TF_TMP="$(mktemp "$PROJECT_DIR/.main.XXXXXX.tf")"

cat > "$MAIN_TF_TMP" <<'EOF'
resource "aws_instance" "devops-school-level3" {
  ami             = var.ami_id
  instance_type   = var.ec2_type
    subnet_id                  = var.subnet_id
  associate_public_ip_address = true
  key_name                   = var.keypair

  vpc_security_group_ids = [var.main_sg_id]

  user_data = file("user-data.web.sh")
  user_data_replace_on_change = true

  tags = {
    Name = var.ec2_name
  }
}
output "ec2_public_dns_name" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_instance.devops-school-level3.public_dns
}
EOF

# - atomically replace main.tf after successful file creation
mv -- "$MAIN_TF_TMP" "main.tf"
MAIN_TF_TMP=""

# - define the permitted deployment context
EXPECTED_AWS_ACCOUNT_ID="441186132708"
EXPECTED_AWS_REGION="eu-north-1"
EXPECTED_TERRAFORM_WORKSPACE="default"

if ! command -v aws >/dev/null 2>&1; then
  printf 'ERROR: AWS CLI saknas.\n' >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'ERROR: jq saknas.\n' >&2
  exit 1
fi

# - verify the authenticated AWS account
if ! CURRENT_AWS_ACCOUNT_ID="$(
  aws sts get-caller-identity --query Account --output text
)"; then
  printf 'ERROR: AWS-identiteten kunde inte verifieras.\n' >&2
  exit 1
fi

if [[ "$CURRENT_AWS_ACCOUNT_ID" != "$EXPECTED_AWS_ACCOUNT_ID" ]]; then
  printf 'ERROR: Fel AWS-konto. Förväntade %s men fick %s.\n' \
    "$EXPECTED_AWS_ACCOUNT_ID" "$CURRENT_AWS_ACCOUNT_ID" >&2
  exit 1
fi

# - verify and lock the AWS region
CURRENT_AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"

if [[ -z "$CURRENT_AWS_REGION" ]]; then
  CURRENT_AWS_REGION="$(aws configure get region 2>/dev/null || true)"
fi

if [[ "$CURRENT_AWS_REGION" != "$EXPECTED_AWS_REGION" ]]; then
  printf 'ERROR: Fel AWS-region. Förväntade %s men fick %s.\n' \
    "$EXPECTED_AWS_REGION" "${CURRENT_AWS_REGION:-inte angiven}" >&2
  exit 1
fi

export AWS_REGION="$EXPECTED_AWS_REGION"
export AWS_DEFAULT_REGION="$EXPECTED_AWS_REGION"

# - initialize the Terraform working directory
terraform init -input=false

# - verify the active Terraform workspace
CURRENT_TERRAFORM_WORKSPACE="$(terraform workspace show)"

if [[ "$CURRENT_TERRAFORM_WORKSPACE" != \
  "$EXPECTED_TERRAFORM_WORKSPACE" ]]; then
  printf 'ERROR: Fel Terraform-workspace. Förväntade %s men fick %s.\n' \
    "$EXPECTED_TERRAFORM_WORKSPACE" \
    "$CURRENT_TERRAFORM_WORKSPACE" >&2
  exit 1
fi

# - verify canonical Terraform formatting
terraform fmt -check -recursive

# - validate the Terraform configuration
terraform validate

# - create a saved Terraform plan
terraform plan -out=tfplan

# - calculate the scope of the saved plan
PLAN_COUNTS="$(
  terraform show -json tfplan |
    jq -er '[
      ([.resource_changes[]? |
        select(.change.actions | index("create"))] | length),
      ([.resource_changes[]? |
        select(.change.actions == ["update"])] | length),
      ([.resource_changes[]? |
        select(.change.actions | index("delete"))] | length)
    ] | @tsv'
)"

IFS=$'\t' read -r \
  PLAN_ADD_COUNT \
  PLAN_CHANGE_COUNT \
  PLAN_DESTROY_COUNT <<< "$PLAN_COUNTS"

printf '\nKontrollerad miljö:\n'
printf '  AWS-konto: %s\n' "$CURRENT_AWS_ACCOUNT_ID"
printf '  AWS-region: %s\n' "$CURRENT_AWS_REGION"
printf '  Terraform-workspace: %s\n' \
  "$CURRENT_TERRAFORM_WORKSPACE"

printf '\nTerraform-plan:\n'
printf '  Add: %s\n' "$PLAN_ADD_COUNT"
printf '  Change: %s\n' "$PLAN_CHANGE_COUNT"
printf '  Destroy: %s\n' "$PLAN_DESTROY_COUNT"

if (( PLAN_DESTROY_COUNT > 0 )); then
  printf 'VARNING: Planen innehåller resurser som ska förstöras.\n' >&2
fi

# - require explicit approval before applying the saved plan
APPLY_CONFIRMATION=""

if ! read -r -p \
  'Skriv APPLY för att tillämpa exakt denna plan: ' \
  APPLY_CONFIRMATION; then
  printf '\nERROR: Bekräftelse kunde inte läsas.\n' >&2
  exit 1
fi

if [[ "$APPLY_CONFIRMATION" != "APPLY" ]]; then
  printf 'Terraform apply avbröts utan ändringar.\n'
  exit 1
fi

terraform apply "tfplan"
# ec2_public_dns_name = "ec2-13-48-135-138.eu-north-1.compute.amazonaws.com"

MY_EC2="$(terraform output -raw ec2_public_dns_name)"

if [[ -z "$MY_EC2" || "$MY_EC2" == "null" ]]; then
  printf 'ERROR: Terraform returned an empty or null ec2_public_dns_name output.\n' >&2
  exit 1
fi

EC2_DNS_PATTERN='^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$'

if (( ${#MY_EC2} > 253 )) || [[ ! "$MY_EC2" =~ $EC2_DNS_PATTERN ]]; then
  printf 'ERROR: Terraform returned an invalid ec2_public_dns_name: %s\n' "$MY_EC2" >&2
  exit 1
fi

MY_SSH="${MY_SSH:-$HOME/.ssh/petter-ec2-key.pem}"

if [[ ! -f "$MY_SSH" || ! -r "$MY_SSH" ]]; then
  printf 'ERROR: SSH-nyckeln saknas eller är inte läsbar: %s\n' "$MY_SSH" >&2
  exit 1
fi

SSH_OPTIONS=(-i "$MY_SSH")

SSH_WAIT_OPTIONS=(
  -o BatchMode=yes
  -o ConnectTimeout=5
  -o ConnectionAttempts=1
  -o StrictHostKeyChecking=accept-new
)

SSH_MAX_ATTEMPTS=24
SSH_RETRY_DELAY=5
ssh_ready=false

for ((ssh_attempt = 1; ssh_attempt <= SSH_MAX_ATTEMPTS; ssh_attempt++)); do
  if ssh "${SSH_OPTIONS[@]}" "${SSH_WAIT_OPTIONS[@]}" \
    "ec2-user@$MY_EC2" true >/dev/null 2>&1; then
    ssh_ready=true
    printf 'SSH is available after attempt %d of %d.\n' \
      "$ssh_attempt" "$SSH_MAX_ATTEMPTS"
    break
  fi

  printf 'Waiting for SSH, attempt %d of %d failed.\n' \
    "$ssh_attempt" "$SSH_MAX_ATTEMPTS"

  if ((ssh_attempt < SSH_MAX_ATTEMPTS)); then
    sleep "$SSH_RETRY_DELAY"
  fi
done

if [[ "$ssh_ready" != true ]]; then
  printf 'ERROR: SSH did not become available after %d attempts.\n' \
    "$SSH_MAX_ATTEMPTS" >&2
  exit 1
fi

# DMC-021: wait for cloud-init to finish and verify successful status.
CLOUD_INIT_TIMEOUT=600

if ! command -v timeout >/dev/null 2>&1; then
  printf 'ERROR: Required command is missing: timeout\n' >&2
  exit 1
fi

if CLOUD_INIT_OUTPUT="$(
  timeout --foreground "${CLOUD_INIT_TIMEOUT}s" \
    ssh "${SSH_OPTIONS[@]}" "${SSH_WAIT_OPTIONS[@]}" \
    "ec2-user@$MY_EC2" \
    'sudo cloud-init status --wait --long' 2>&1
)"; then
  printf '%s\n' "$CLOUD_INIT_OUTPUT"
else
  cloud_init_status=$?
  printf 'ERROR: cloud-init did not complete successfully within %d seconds (exit code %d).\n' \
    "$CLOUD_INIT_TIMEOUT" "$cloud_init_status" >&2
  printf '%s\n' "$CLOUD_INIT_OUTPUT" >&2
  exit 1
fi

if ! grep -Eq '^status:[[:space:]]+done[[:space:]]*$' \
  <<< "$CLOUD_INIT_OUTPUT"; then
  printf 'ERROR: cloud-init completed without reporting status: done.\n' >&2
  exit 1
fi

# DMC-022 through DMC-033: transactional, non-interactive remote deploy.
APP_REPO_URL='https://github.com/nenemustafa/Hellome.git'
APP_SOURCE_RELATIVE_PATH='heyme'
EXPECTED_MARKER='Hey me!'
REMOTE_WEB_ROOT='/usr/share/nginx/html'
DEPLOY_ID="dmc-$(date -u +'%Y%m%dT%H%M%SZ')-$$"
REMOTE_STAGE_DIR="/usr/share/nginx/.html-stage-$DEPLOY_ID"
REMOTE_BACKUP_DIR="/usr/share/nginx/.html-backup-$DEPLOY_ID"
REMOTE_BACKUP_READY="${REMOTE_BACKUP_DIR}.ready"
deployment_started=false
deployment_committed=false

rollback_remote_deploy() {
  ssh "${SSH_OPTIONS[@]}" "${SSH_WAIT_OPTIONS[@]}" \
    "ec2-user@$MY_EC2" \
    bash -s -- \
      "$REMOTE_WEB_ROOT" \
      "$REMOTE_STAGE_DIR" \
      "$REMOTE_BACKUP_DIR" \
      "$REMOTE_BACKUP_READY" <<'REMOTE_ROLLBACK'
set -Eeuo pipefail

REMOTE_WEB_ROOT=$1
REMOTE_STAGE_DIR=$2
REMOTE_BACKUP_DIR=$3
REMOTE_BACKUP_READY=$4

case "$REMOTE_WEB_ROOT" in
  /usr/share/nginx/html) ;;
  *)
    printf 'ERROR: Refusing rollback for unsafe web root: %s\n' \
      "$REMOTE_WEB_ROOT" >&2
    exit 1
    ;;
esac

case "$REMOTE_STAGE_DIR" in
  /usr/share/nginx/.html-stage-dmc-*) ;;
  *)
    printf 'ERROR: Refusing unsafe stage path: %s\n' \
      "$REMOTE_STAGE_DIR" >&2
    exit 1
    ;;
esac

case "$REMOTE_BACKUP_DIR" in
  /usr/share/nginx/.html-backup-dmc-*) ;;
  *)
    printf 'ERROR: Refusing unsafe backup path: %s\n' \
      "$REMOTE_BACKUP_DIR" >&2
    exit 1
    ;;
esac

if [[ "$REMOTE_BACKUP_READY" != "${REMOTE_BACKUP_DIR}.ready" ]]; then
  printf 'ERROR: Refusing inconsistent backup marker path: %s\n' \
    "$REMOTE_BACKUP_READY" >&2
  exit 1
fi

if sudo test -f "$REMOTE_BACKUP_READY"; then
  if ! sudo test -d "$REMOTE_BACKUP_DIR"; then
    printf 'ERROR: Rollback marker exists but backup directory is missing.\n' >&2
    exit 1
  fi

  sudo find "$REMOTE_WEB_ROOT" -mindepth 1 -maxdepth 1 \
    -exec rm -rf -- {} +

  sudo cp -a -- "$REMOTE_BACKUP_DIR"/. "$REMOTE_WEB_ROOT"/
  sudo nginx -t

  printf 'Previous web deployment restored successfully.\n'
else
  printf 'No completed web backup was present; active web root was left unchanged.\n'
fi

sudo rm -rf -- "$REMOTE_STAGE_DIR" "$REMOTE_BACKUP_DIR"
sudo rm -f -- "$REMOTE_BACKUP_READY"
REMOTE_ROLLBACK
}

finalize_remote_deploy() {
  ssh "${SSH_OPTIONS[@]}" "${SSH_WAIT_OPTIONS[@]}" \
    "ec2-user@$MY_EC2" \
    bash -s -- \
      "$REMOTE_STAGE_DIR" \
      "$REMOTE_BACKUP_DIR" \
      "$REMOTE_BACKUP_READY" <<'REMOTE_FINALIZE'
set -Eeuo pipefail

REMOTE_STAGE_DIR=$1
REMOTE_BACKUP_DIR=$2
REMOTE_BACKUP_READY=$3

case "$REMOTE_STAGE_DIR" in
  /usr/share/nginx/.html-stage-dmc-*) ;;
  *)
    printf 'ERROR: Refusing unsafe stage path: %s\n' \
      "$REMOTE_STAGE_DIR" >&2
    exit 1
    ;;
esac

case "$REMOTE_BACKUP_DIR" in
  /usr/share/nginx/.html-backup-dmc-*) ;;
  *)
    printf 'ERROR: Refusing unsafe backup path: %s\n' \
      "$REMOTE_BACKUP_DIR" >&2
    exit 1
    ;;
esac

if [[ "$REMOTE_BACKUP_READY" != "${REMOTE_BACKUP_DIR}.ready" ]]; then
  printf 'ERROR: Refusing inconsistent backup marker path: %s\n' \
    "$REMOTE_BACKUP_READY" >&2
  exit 1
fi

if ! sudo test -f "$REMOTE_BACKUP_READY"; then
  printf 'ERROR: Deployment cannot be finalized because the backup marker is missing.\n' >&2
  exit 1
fi

sudo rm -rf -- "$REMOTE_STAGE_DIR" "$REMOTE_BACKUP_DIR"
sudo rm -f -- "$REMOTE_BACKUP_READY"

printf 'Remote deployment transaction finalized.\n'
REMOTE_FINALIZE
}

finish_deployment_run() {
  local status=$?
  local rollback_status=0
  local cleanup_status=0

  trap - EXIT
  set +e

  if [[ "$deployment_started" == true &&
        "$deployment_committed" != true ]]; then
    printf 'Deployment was not committed; attempting web rollback.\n' >&2
    rollback_remote_deploy
    rollback_status=$?
  fi

  cleanup_temp_files
  cleanup_status=$?

  if ((rollback_status != 0)); then
    printf 'ERROR: Web rollback failed. Manual recovery may be required.\n' >&2
    status=1
  elif ((status == 0 && cleanup_status != 0)); then
    status=$cleanup_status
  fi

  exit "$status"
}

# Replace the earlier temporary-file-only EXIT trap with combined cleanup.
trap finish_deployment_run EXIT
deployment_started=true

if ! ssh "${SSH_OPTIONS[@]}" "${SSH_WAIT_OPTIONS[@]}" \
  "ec2-user@$MY_EC2" \
  bash -s -- \
    "$APP_REPO_URL" \
    "$APP_SOURCE_RELATIVE_PATH" \
    "$REMOTE_WEB_ROOT" \
    "$REMOTE_STAGE_DIR" \
    "$REMOTE_BACKUP_DIR" \
    "$REMOTE_BACKUP_READY" <<'REMOTE_DEPLOY'
set -Eeuo pipefail

APP_REPO_URL=$1
APP_SOURCE_RELATIVE_PATH=$2
REMOTE_WEB_ROOT=$3
REMOTE_STAGE_DIR=$4
REMOTE_BACKUP_DIR=$5
REMOTE_BACKUP_READY=$6
EXPECTED_MARKER='Hey me!'
REMOTE_WORK_DIR=''

cleanup_remote_workdir() {
  if [[ -n "$REMOTE_WORK_DIR" ]]; then
    case "$REMOTE_WORK_DIR" in
      /tmp/hellome-deploy.*)
        rm -rf -- "$REMOTE_WORK_DIR"
        ;;
      *)
        printf 'WARNING: Refusing to remove unsafe work path: %s\n' \
          "$REMOTE_WORK_DIR" >&2
        ;;
    esac
  fi
}

trap cleanup_remote_workdir EXIT

case "$APP_SOURCE_RELATIVE_PATH" in
  ''|/*|*..*)
    printf 'ERROR: Unsafe application source path: %s\n' \
      "$APP_SOURCE_RELATIVE_PATH" >&2
    exit 1
    ;;
esac

case "$REMOTE_WEB_ROOT" in
  /usr/share/nginx/html) ;;
  *)
    printf 'ERROR: Refusing unsafe web root: %s\n' \
      "$REMOTE_WEB_ROOT" >&2
    exit 1
    ;;
esac

case "$REMOTE_STAGE_DIR" in
  /usr/share/nginx/.html-stage-dmc-*) ;;
  *)
    printf 'ERROR: Refusing unsafe stage path: %s\n' \
      "$REMOTE_STAGE_DIR" >&2
    exit 1
    ;;
esac

case "$REMOTE_BACKUP_DIR" in
  /usr/share/nginx/.html-backup-dmc-*) ;;
  *)
    printf 'ERROR: Refusing unsafe backup path: %s\n' \
      "$REMOTE_BACKUP_DIR" >&2
    exit 1
    ;;
esac

if [[ "$REMOTE_BACKUP_READY" != "${REMOTE_BACKUP_DIR}.ready" ]]; then
  printf 'ERROR: Refusing inconsistent backup marker path: %s\n' \
    "$REMOTE_BACKUP_READY" >&2
  exit 1
fi

for required_command in git mktemp sudo grep; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'ERROR: Required remote command is missing: %s\n' \
      "$required_command" >&2
    exit 1
  fi
done

if ! sudo -n true; then
  printf 'ERROR: Passwordless sudo is required for non-interactive deployment.\n' >&2
  exit 1
fi

if ! sudo test -d "$REMOTE_WEB_ROOT" ||
   sudo test -L "$REMOTE_WEB_ROOT"; then
  printf 'ERROR: Nginx web root is missing or is an unsupported symbolic link: %s\n' \
    "$REMOTE_WEB_ROOT" >&2
  exit 1
fi

if ! sudo systemctl is-active --quiet nginx; then
  printf 'ERROR: Nginx is not active.\n' >&2
  exit 1
fi

if ! sudo nginx -t; then
  printf 'ERROR: Nginx configuration validation failed before deployment.\n' >&2
  exit 1
fi

if ! git ls-remote --exit-code "$APP_REPO_URL" HEAD \
  >/dev/null 2>&1; then
  printf 'ERROR: Git repository is unavailable: %s\n' \
    "$APP_REPO_URL" >&2
  exit 1
fi

REMOTE_WORK_DIR="$(mktemp -d /tmp/hellome-deploy.XXXXXX)"
REMOTE_APP_DIR="$REMOTE_WORK_DIR/Hellome"
REMOTE_SOURCE_DIR="$REMOTE_WORK_DIR/site"

git clone --depth 1 --branch main --single-branch \
  "$APP_REPO_URL" "$REMOTE_APP_DIR"

REMOTE_SOURCE_FILE="$REMOTE_APP_DIR/$APP_SOURCE_RELATIVE_PATH"

if [[ ! -f "$REMOTE_SOURCE_FILE" ||
      ! -r "$REMOTE_SOURCE_FILE" ||
      ! -s "$REMOTE_SOURCE_FILE" ]]; then
  printf 'ERROR: Required application file is missing, unreadable, or empty: %s\n' \
    "$REMOTE_SOURCE_FILE" >&2
  exit 1
fi

if ! grep -Eqi '<!doctype[[:space:]]+html' \
  "$REMOTE_SOURCE_FILE"; then
  printf 'ERROR: Application source is not recognized as HTML: %s\n' \
    "$REMOTE_SOURCE_FILE" >&2
  exit 1
fi

if ! grep -Fqi "$EXPECTED_MARKER" "$REMOTE_SOURCE_FILE"; then
  printf 'ERROR: Expected marker is missing from application source: %s\n' \
    "$EXPECTED_MARKER" >&2
  exit 1
fi

mkdir -p "$REMOTE_SOURCE_DIR"
cp -a -- "$REMOTE_SOURCE_FILE" "$REMOTE_SOURCE_DIR/index.html"

sudo rm -rf -- "$REMOTE_STAGE_DIR" "$REMOTE_BACKUP_DIR"
sudo rm -f -- "$REMOTE_BACKUP_READY"
sudo mkdir -p "$REMOTE_STAGE_DIR" "$REMOTE_BACKUP_DIR"

# Copy the entire prepared tree, including hidden files and directories.
sudo cp -a -- "$REMOTE_SOURCE_DIR"/. "$REMOTE_STAGE_DIR"/

if ! sudo test -s "$REMOTE_STAGE_DIR/index.html" ||
   ! sudo grep -Fqi "$EXPECTED_MARKER" \
     "$REMOTE_STAGE_DIR/index.html"; then
  printf 'ERROR: Staged application validation failed; active web root was not changed.\n' >&2
  exit 1
fi

# Preserve the complete previous web tree before changing active content.
sudo cp -a -- "$REMOTE_WEB_ROOT"/. "$REMOTE_BACKUP_DIR"/
sudo touch "$REMOTE_BACKUP_READY"

# Replace all entries, including hidden files and directories.
sudo find "$REMOTE_WEB_ROOT" -mindepth 1 -maxdepth 1 \
  -exec rm -rf -- {} +

sudo cp -a -- "$REMOTE_STAGE_DIR"/. "$REMOTE_WEB_ROOT"/

if ! sudo test -s "$REMOTE_WEB_ROOT/index.html" ||
   ! sudo grep -Fqi "$EXPECTED_MARKER" \
     "$REMOTE_WEB_ROOT/index.html"; then
  printf 'ERROR: Deployed application validation failed; rollback is required.\n' >&2
  exit 1
fi

if ! sudo nginx -t; then
  printf 'ERROR: Nginx validation failed after deployment; rollback is required.\n' >&2
  exit 1
fi

printf 'Remote application staged and deployed; backup retained pending HTTP verification.\n'
REMOTE_DEPLOY
then
  printf 'ERROR: Remote deployment failed.\n' >&2
  exit 1
fi

HTTP_MAX_ATTEMPTS=12
HTTP_RETRY_DELAY=5
HTTP_CONNECT_TIMEOUT=5
HTTP_MAX_TIME=15
http_verified=false

for ((http_attempt = 1;
      http_attempt <= HTTP_MAX_ATTEMPTS;
      http_attempt++)); do

  if http_body="$(
    curl --fail --silent --show-error --location \
      --connect-timeout "$HTTP_CONNECT_TIMEOUT" \
      --max-time "$HTTP_MAX_TIME" \
      "http://$MY_EC2/" 2>&1
  )"; then
    normalized_http_body="$(
      tr '\r\n\t' '   ' <<< "$http_body" |
        tr -s '[:space:]' ' '
    )"

    if grep -Fqi "$EXPECTED_MARKER" \
      <<< "$normalized_http_body"; then
      http_verified=true
      printf 'HTTP verification succeeded on attempt %d of %d.\n' \
        "$http_attempt" "$HTTP_MAX_ATTEMPTS"
      break
    fi

    printf 'HTTP attempt %d of %d returned content without the expected marker.\n' \
      "$http_attempt" "$HTTP_MAX_ATTEMPTS" >&2
  else
    printf 'HTTP attempt %d of %d failed: %s\n' \
      "$http_attempt" "$HTTP_MAX_ATTEMPTS" \
      "$http_body" >&2
  fi

  if ((http_attempt < HTTP_MAX_ATTEMPTS)); then
    sleep "$HTTP_RETRY_DELAY"
  fi
done

if [[ "$http_verified" != true ]]; then
  printf 'ERROR: HTTP verification failed after %d attempts; rollback will run.\n' \
    "$HTTP_MAX_ATTEMPTS" >&2
  exit 1
fi

if ! finalize_remote_deploy; then
  printf 'ERROR: Remote deployment finalization failed; rollback will run.\n' >&2
  exit 1
fi

deployment_committed=true

printf 'Deployment completed and verified successfully: http://%s/\n' \
  "$MY_EC2"
