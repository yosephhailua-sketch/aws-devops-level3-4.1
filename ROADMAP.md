# AWS DevOps Level 3 – Roadmap

## Status legend

- ✅ Completed
- 🔄 In progress
- ⏳ Planned

## Milestone 1 – Terraform foundation ✅

- [x] AWS provider configuration
- [x] configurable region and EC2 settings
- [x] managed security group
- [x] EC2 instance deployment
- [x] Terraform outputs
- [x] Amazon Linux 2023 support
- [x] IMDSv2 enforcement

## Milestone 2 – Defect Management Cycle ✅

- [x] preserve the original Iteration 2 script
- [x] identify defects DMC-001 through DMC-033
- [x] create corrected working version
- [x] preserve verification evidence
- [x] complete syntax and quality validation
- [x] remove destructive and misleading behavior

## Milestone 3 – Level 3 final iterations ✅

- [x] Iteration 3 workflow
- [x] Iteration 4 workflow
- [x] consolidated Level 3 final script
- [x] user-data and Nginx deployment
- [x] live AWS verification

## Milestone 4 – Level 4 Iteration 1 ✅

- [x] strict Bash execution mode
- [x] portable project-directory handling
- [x] dependency checks
- [x] AWS value validation
- [x] VPC, subnet, AMI and key-pair validation
- [x] safe tfvars generation and backup
- [x] saved-plan collision protection
- [x] manual plan review and apply
- [x] successful EC2 replacement
- [x] successful web deployment
- [x] zero-drift post-apply verification

## Milestone 5 – Public GitHub delivery 🔄

- [x] remove secrets and local Terraform artifacts
- [x] normalize repository line endings
- [x] add repository security rules
- [x] create project report
- [x] create roadmap
- [x] create security policy
- [ ] complete final public-release scan
- [ ] publish repository to GitHub
- [ ] verify the public repository contents

## Milestone 6 – CI quality gates ⏳

- [ ] add GitHub Actions
- [ ] run Terraform formatting checks
- [ ] run Terraform validation
- [ ] run Bash syntax and ShellCheck
- [ ] add automated secret scanning
- [ ] add Markdown quality checks

## Milestone 7 – State and infrastructure hardening ⏳

- [ ] migrate Terraform state to a protected remote backend
- [ ] add state locking
- [ ] use least-privilege IAM roles
- [ ] pin external source revisions
- [ ] add HTTPS and certificate management
- [ ] evaluate IPv6 support
- [ ] add monitoring and alerting

## Milestone 8 – Production-style architecture ⏳

- [ ] separate reusable Terraform modules
- [ ] introduce development and test environments
- [ ] evaluate load balancing and autoscaling
- [ ] add automated integration testing
- [ ] document disaster recovery
- [ ] add budget alerts and cleanup automation
