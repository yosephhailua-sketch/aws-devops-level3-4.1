# Level 4 – Iteration 3 Handbook

## What this iteration does

Iteration 3 safely refactors an existing Terraform project so stable AWS resource values are resolved dynamically instead of being stored as several manual entries in `terraform.tfvars`.

The workflow is designed for an already deployed environment. Its first responsibility is therefore preservation: it inspects the current Terraform state and AWS resources, pins values that could force EC2 replacement, creates a recovery backup, validates the refactor, and blocks destructive plans unless the operator explicitly overrides the protection.

## Final result

The verified run completed with:

| Check | Result |
| --- | --- |
| Preflight | Passed |
| Terraform syntax and validation | Passed |
| Planned resource creation | 0 |
| Planned in-place changes | 1 |
| Planned destroy or replacement | 0 |
| Applied change | EC2 `Name` tag only |
| Post-apply drift | None |
| Website HTTP test | Passed |

No EC2 instance, volume, network interface, security group, or public endpoint was replaced by the completed workflow.

## Files involved

- `Level4-Iteration3.sh` performs discovery, backup, refactoring, validation, planning, optional apply, web testing, and optional Git actions.
- `iteration3.tf` contains the generated dynamic lookups and derived local values.
- `main.tf` consumes the derived AMI, subnet, key-pair, name, and security-group values.
- `variables.tf` keeps only genuinely configurable variables.
- `terraform.tfvars` remains local and contains environment-specific input such as `aws_owner` and `ssh_cidr`.
- `.level4-iteration3-backups/` contains timestamped recovery copies and is ignored by Git.

## Safety model

The script uses the following control sequence:

1. Validate required commands, the Terraform project, AWS credentials, and region.
2. Resolve the current AMI, subnet, security group, key pair, owner, and SSH CIDR.
3. Stop immediately when a required value is ambiguous or missing.
4. Back up every project file that may be changed.
5. Patch the existing Terraform files and create `iteration3.tf`.
6. Run formatting, initialization, and configuration validation.
7. Create a saved Terraform plan and inspect its machine-readable actions.
8. Restore the original files when validation fails or the plan contains a blocked deletion or replacement.
9. Apply only when `--apply` is supplied and the operator confirms.
10. Test the website and report the final drift state.

`--allow-destroy` only permits review of a destructive plan. It does not imply `--apply`.

## Requirements

- Bash
- AWS CLI with an active authenticated profile
- Terraform
- Python 3
- Git
- `curl` for the web test
- an existing Terraform-managed EC2 deployment

Confirm the active AWS session before running the workflow:

```bash
aws sts get-caller-identity
terraform version
```

If an AWS IAM Identity Center session has expired, authenticate the intended profile again before running Terraform.

## Recommended commands

Run these commands from the Terraform repository root.

### 1. Preflight only

```bash
bash "Level4/Iteration3/Level4-Iteration3.sh" \
  --project-dir "$PWD" \
  --owner "YOUR_OWNER" \
  --ami-id "CURRENT_AMI_ID" \
  --sg-name "EXISTING_SECURITY_GROUP" \
  --check-only
```

This changes neither files nor infrastructure.

### 2. Refactor and review the plan

```bash
bash "Level4/Iteration3/Level4-Iteration3.sh" \
  --project-dir "$PWD" \
  --owner "YOUR_OWNER" \
  --ami-id "CURRENT_AMI_ID" \
  --sg-name "EXISTING_SECURITY_GROUP"
```

Answer `y` only after confirming the displayed project path. The script creates a backup before editing.

The safe expected plan is:

```text
Plan: 0 to add, 1 to change, 0 to destroy.
```

Review the complete plan. Do not apply when the output contains an unexpected `-/+`, `destroy`, AMI change, subnet change, key-pair change, or security-group removal.

### 3. Apply the reviewed change

```bash
bash "Level4/Iteration3/Level4-Iteration3.sh" \
  --project-dir "$PWD" \
  --owner "YOUR_OWNER" \
  --ami-id "CURRENT_AMI_ID" \
  --sg-name "EXISTING_SECURITY_GROUP" \
  --apply
```

The script creates a new saved plan for the apply run. Confirm only if that plan still matches the reviewed intent.

### 4. Verify manually

```bash
terraform plan
terraform output
git --no-pager diff --check
git --no-pager status --short
```

A completed environment should report no Terraform changes, and the website test should return a successful HTTP response.

## Important options

| Option | Purpose |
| --- | --- |
| `--check-only` | Validate prerequisites without editing files or infrastructure |
| `--ami-id AMI` | Preserve or explicitly pin an existing AMI |
| `--latest-ami` | Select the latest AL2023 SSM AMI; may replace EC2 |
| `--sg-name NAME` | Select an existing security group by its exact name |
| `--key-name NAME` | Select an existing EC2 key pair by its exact name |
| `--no-key-pair` | Preserve an instance that intentionally has no key pair |
| `--ssh-cidr CIDR` | Set a narrow IPv4 CIDR for SSH access |
| `--apply` | Apply the exact saved plan after confirmation |
| `--allow-destroy` | Permit a plan with deletes or replacements for explicit review |
| `--skip-web-test` | Skip the HTTP verification |
| `--commit` | Commit only the script-managed refactor files |
| `--push` | Commit and push after all validation succeeds |

Run `bash "Level4/Iteration3/Level4-Iteration3.sh" --help` for the complete interface.

## Why the AMI is pinned

An EC2 AMI is immutable. Changing the AMI on an existing `aws_instance` forces replacement. Iteration 3 therefore preserves the currently deployed AMI unless `--latest-ami` is explicitly selected.

Use `--latest-ami` only as a reviewed upgrade operation where instance replacement, a new public address, bootstrap execution, and service verification are expected.

## Why two security groups may appear

The existing EC2 instance can use both:

- the Terraform-managed web security group; and
- an existing additional security group resolved by exact name.

Removing either group unintentionally would change network access. Iteration 3 resolves and preserves the additional group while the managed group remains under Terraform control.

## Recovery

Each refactor creates a directory similar to:

```text
.level4-iteration3-backups/YYYYMMDDTHHMMSSZ.random/
```

When validation does not finish safely, the script automatically restores the original project files and keeps the backup for inspection.

For a manual recovery, first stop all Terraform activity, inspect the backup, and copy only the required project files back into the repository. Never restore `.terraform/`, saved plans, or state files from this directory without separately validating the backend and state ownership.

## Git release checklist

- [ ] `terraform fmt -check -recursive` passes
- [ ] `terraform validate` passes
- [ ] `terraform plan` reports no unintended changes
- [ ] `bash -n Level4/Iteration3/Level4-Iteration3.sh` passes
- [ ] `git diff --cached --check` passes
- [ ] staged files contain no credentials, private keys, state, plans, or personal SSH CIDR
- [ ] unrelated working-tree changes remain unstaged
- [ ] the cached diff is reviewed before commit

The script never requires automatic Git actions. Manual review remains the recommended release path.
