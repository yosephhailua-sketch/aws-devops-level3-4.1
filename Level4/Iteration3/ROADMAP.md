# Level 4 – Iteration 3 Roadmap

## Goal

Refactor the existing Terraform configuration to use reliable AWS lookups while preserving the live deployment and enforcing a review-first workflow.

## Phase 1 – Discovery and preflight ✅

- [x] validate Bash, AWS CLI, Terraform, Python, Git, and curl
- [x] validate the Terraform project directory
- [x] verify the active AWS identity and region
- [x] preserve the existing owner and SSH CIDR inputs
- [x] resolve the current EC2 instance from Terraform state
- [x] resolve the current AMI and key pair
- [x] support exact security-group selection with `--sg-name`
- [x] support exact key-pair selection with `--key-name`
- [x] support an intentional no-key-pair configuration

## Phase 2 – Safe Terraform refactor ✅

- [x] create timestamped recovery backups
- [x] update `.gitignore` for the recovery directory
- [x] create the managed `iteration3.tf` file
- [x] patch existing resource references instead of replacing whole files blindly
- [x] reduce `terraform.tfvars` to environment-specific inputs
- [x] keep the current AMI pinned by default
- [x] make the latest AL2023 AMI an explicit opt-in
- [x] preserve the managed and additional security groups
- [x] preserve the current subnet and key pair
- [x] run Terraform formatting and validation

## Phase 3 – Plan protection ✅

- [x] create a unique saved plan
- [x] inspect plan actions in machine-readable form
- [x] block delete and replacement actions by default
- [x] prove automatic file restoration after a blocked replacement plan
- [x] produce a safe plan with `0 add, 1 change, 0 destroy`
- [x] confirm that the only planned change is the EC2 `Name` tag

## Phase 4 – Apply and live verification ✅

- [x] require explicit `--apply`
- [x] apply the reviewed in-place change
- [x] verify that Terraform reports no remaining drift
- [x] verify a successful HTTP response from the website
- [x] leave Git unchanged for manual review

## Phase 5 – Documentation and evidence ✅

- [x] create the Iteration 3 handbook
- [x] create the Iteration 3 roadmap
- [x] update the root project README and roadmap
- [x] record DMC-034 preflight evidence
- [x] record DMC-035 destructive-plan protection evidence
- [x] record DMC-036 safe-plan evidence
- [x] record DMC-037 apply and live-verification evidence

## Phase 6 – GitHub release 🔄

- [ ] inspect the complete staged diff
- [ ] run the final Terraform, Bash, Markdown, and secret checks
- [ ] commit the Iteration 3 implementation and documentation
- [ ] push the reviewed commit to GitHub
- [ ] inspect the repository through GitHub
- [ ] confirm that no local inputs or infrastructure state were published

## Later improvements ⏳

- [ ] add CI checks for Terraform and Bash
- [ ] add ShellCheck and secret scanning
- [ ] create an intentional AMI-upgrade runbook
- [ ] add HTTPS and certificate management
- [ ] add monitoring, alerts, and recovery exercises
