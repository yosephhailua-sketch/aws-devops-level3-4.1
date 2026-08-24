# DevOps Starter Pack Deluxe Edition

AWS DevOps learning project with a Terraform-managed EC2 web server and safe Bash workflows for validation, refactoring, deployment, and verification.

The repository began as an AWS DevOps Level 3 project. Level 4 adds guarded automation around the existing infrastructure without silently replacing live resources.

## Current status

- Terraform configuration is valid.
- The existing EC2 instance is managed without infrastructure drift.
- Amazon Linux 2023, Nginx, cloud-init, and IMDSv2 are in use.
- Level 4 Iteration 3 completed with a non-destructive apply.
- The live HTTP verification passed.
- Git commits and pushes remain explicit manual actions.

See [ROADMAP.md](ROADMAP.md) for completed and planned milestones.

## Technologies

- Terraform
- AWS EC2, VPC, subnets, security groups, and Systems Manager Parameter Store
- Amazon Linux 2023
- Cloud-init
- Nginx
- Bash
- Git and GitHub

## Repository structure

| Path | Purpose |
| --- | --- |
| `main.tf` | EC2 instance and managed web security group |
| `variables.tf` | Environment inputs that remain configurable |
| `iteration3.tf` | Dynamic AWS lookups and derived resource values |
| `provider.tf` | AWS provider and Terraform configuration |
| `outputs.tf` | Instance and website outputs |
| `user-data.web.sh` | EC2 bootstrap script for the web server |
| `html/` | Website content |
| `Level4/Iteration3/` | Iteration 3 workflow, handbook, and roadmap |
| `DMC/03-evidence/` | Defect-management and verification evidence |

## Deployment model

Terraform manages an EC2 instance and a dedicated security group. The bootstrap script installs and configures Nginx, and the website content is stored under `html/`.

Iteration 3 moves stable resource selection into dynamic AWS lookups while preserving the live instance's AMI, subnet, key pair, and additional security group. Only environment-specific values remain in the ignored local `terraform.tfvars` file.

## Safe Iteration 3 workflow

Start with preflight validation:

```bash
bash "Level4/Iteration3/Level4-Iteration3.sh" \
  --project-dir "$PWD" \
  --owner "YOUR_OWNER" \
  --ami-id "CURRENT_AMI_ID" \
  --sg-name "EXISTING_SECURITY_GROUP" \
  --check-only
```

Generate and review the refactor and saved Terraform plan:

```bash
bash "Level4/Iteration3/Level4-Iteration3.sh" \
  --project-dir "$PWD" \
  --owner "YOUR_OWNER" \
  --ami-id "CURRENT_AMI_ID" \
  --sg-name "EXISTING_SECURITY_GROUP"
```

Apply only after confirming that the plan has no unwanted delete or replacement actions:

```bash
bash "Level4/Iteration3/Level4-Iteration3.sh" \
  --project-dir "$PWD" \
  --owner "YOUR_OWNER" \
  --ami-id "CURRENT_AMI_ID" \
  --sg-name "EXISTING_SECURITY_GROUP" \
  --apply
```

The script blocks destructive plans by default, creates recovery backups, restores files after failed validation, and never commits or pushes unless explicitly requested.

For the full handbook, options, recovery procedure, and verified results, read [Level4/Iteration3/README.md](Level4/Iteration3/README.md).

## Local values and secrets

Do not commit Terraform state, saved plans, `.terraform/`, credentials, private keys, recovery backups, or `terraform.tfvars`. Review `git status` and the staged diff before every public push.

## Verification

The completed Iteration 3 run produced:

- a safe plan with `0 to add, 1 to change, 0 to destroy`;
- an in-place EC2 `Name` tag update;
- a successful apply;
- a zero-drift follow-up plan; and
- a successful HTTP response from the deployed website.

Evidence is recorded in `DMC/03-evidence/DMC-034-test.txt` through `DMC-037-test.txt`.
