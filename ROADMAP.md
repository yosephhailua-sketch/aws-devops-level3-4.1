# AWS DevOps Project Roadmap

## Status legend

- ✅ Completed
- 🔄 In progress
- ⏳ Planned

## Milestone 1 – Terraform foundation ✅

- [x] configure the AWS provider
- [x] make the region and EC2 settings configurable
- [x] manage the web security group
- [x] deploy an EC2 instance
- [x] expose Terraform outputs
- [x] support Amazon Linux 2023
- [x] enforce IMDSv2

## Milestone 2 – Defect Management Cycle ✅

- [x] preserve the original Iteration 2 script
- [x] identify defects DMC-001 through DMC-033
- [x] create a corrected working version
- [x] preserve verification evidence
- [x] complete syntax and quality validation
- [x] remove destructive and misleading behavior

## Milestone 3 – Level 3 final iterations ✅

- [x] complete the Iteration 3 workflow
- [x] complete the Iteration 4 workflow
- [x] consolidate the Level 3 final script
- [x] deploy Nginx through user data
- [x] verify the live AWS deployment

## Milestone 4 – Level 4 Iteration 1 ✅

- [x] enable strict Bash execution mode
- [x] add portable project-directory handling
- [x] validate dependencies and AWS values
- [x] validate the VPC, subnet, AMI, and key pair
- [x] generate and back up local Terraform inputs safely
- [x] protect saved plans from collisions
- [x] require manual plan review and apply authorization
- [x] complete the EC2 and web deployment
- [x] verify zero Terraform drift after apply

## Milestone 5 – Level 4 Iteration 2 ✅

- [x] prepare the shared-state workflow
- [x] preserve and validate the existing infrastructure state
- [x] verify backend initialization and state access
- [x] keep credentials outside the repository
- [x] confirm that Terraform reports no infrastructure drift

## Milestone 6 – Level 4 Iteration 3 ✅

- [x] add preflight-only validation
- [x] discover the active AWS identity, region, and live Terraform resources
- [x] support exact security-group and key-pair selection
- [x] preserve the existing SSH CIDR as a local input
- [x] preserve the current AMI by default
- [x] make the latest Amazon Linux AMI an explicit opt-in upgrade
- [x] refactor static values into dynamic AWS lookups
- [x] reduce `terraform.tfvars` to environment-specific inputs
- [x] create timestamped recovery backups
- [x] restore project files after failed validation or a blocked plan
- [x] block delete and replacement plans by default
- [x] complete a safe in-place apply
- [x] verify zero drift and a successful website response
- [x] record DMC-034 through DMC-037 evidence

See [Level4/Iteration3/ROADMAP.md](Level4/Iteration3/ROADMAP.md) for the detailed workflow and release checklist.

## Milestone 7 – Public GitHub delivery 🔄

- [x] remove secrets and local Terraform artifacts
- [x] normalize repository line endings
- [x] add repository security rules
- [x] create project documentation and a roadmap
- [x] document the latest validated workflow
- [ ] review the complete staged diff
- [ ] complete the final public-release scan
- [ ] publish the repository to GitHub
- [ ] verify the public repository contents

## Milestone 8 – CI quality gates ⏳

- [ ] add GitHub Actions
- [ ] run `terraform fmt -check`
- [ ] run `terraform validate`
- [ ] run Bash syntax checks and ShellCheck
- [ ] add automated secret scanning
- [ ] add Markdown quality checks

## Milestone 9 – Infrastructure hardening ⏳

- [ ] use least-privilege IAM roles
- [ ] pin external source revisions
- [ ] add HTTPS and certificate management
- [ ] evaluate IPv6 support
- [ ] add monitoring and alerting
- [ ] add backup and restore exercises for remote state

## Milestone 10 – Production-style architecture ⏳

- [ ] separate reusable Terraform modules
- [ ] introduce development and test environments
- [ ] evaluate load balancing and autoscaling
- [ ] add automated integration testing
- [ ] document disaster recovery
- [ ] add budget alerts and cleanup automation
