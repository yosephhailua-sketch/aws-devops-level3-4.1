# AWS DevOps Project — Level 3 and Level 4

This repository contains an educational AWS DevOps project covering Terraform infrastructure, Bash automation, defect management, validation, and deployment documentation.

## Technologies

- Terraform
- AWS EC2 and VPC
- Amazon Linux 2023
- Bash
- Cloud-init
- Nginx
- Git and GitHub

## Repository Structure

- `DMC/` — defect management cases and test evidence
- `FINAL/` — final Level 3 scripts
- `Level4/Iteration1/` — Level 4 Iteration 1 working script and original script
- `Level4/Iteration2/` — Level 4 Iteration 2 script
- `main.tf`, `variables.tf`, `provider.tf`, `outputs.tf` — Terraform configuration
- `iteration3.tf` — Level 4 Iteration 3 configuration
- `user-data.web.sh` — EC2 initialization and web-server setup
- `html/index.html` — website content
- `REPORT.md` — project report
- `ROADMAP.md` — project milestones and delivery status
- `SECURITY.md` — security reporting guidance

## Validation

The Level 4 Iteration 1 workflow includes Bash checks, AWS resource validation, Terraform formatting and validation, and creation of a saved plan for manual review.

Review the Terraform configuration and plan carefully before applying infrastructure changes. Do not commit AWS credentials, private keys, Terraform state, variable files containing sensitive values, or saved plans.

## Project Status

Refer to `ROADMAP.md` for the current milestone and public-delivery status.
