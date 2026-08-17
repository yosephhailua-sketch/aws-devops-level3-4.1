# AWS DevOps Level 3 – Project Report

**Author:** Petter Wastesson
**Project type:** School and APL project
**Status:** Completed and verified
**Last updated:** 2026-08-17

## 1. Purpose

The purpose of this project was to build, review and improve an AWS-based
infrastructure deployment using Terraform, Bash, cloud-init, Ansible, Git and
GitHub-oriented DevOps practices.

The work focused on reproducibility, security, validation, documentation and
controlled infrastructure changes.

## 2. Technical scope

The project includes:

- Terraform configuration for AWS
- Amazon EC2 with Amazon Linux 2023
- security groups for HTTP and restricted SSH
- dynamically selected or explicitly supplied AMI
- configurable subnet, key pair and instance type
- cloud-init and Ansible configuration management
- Nginx installation and automatic startup
- deployment of a small HTML application from GitHub
- Terraform outputs for instance ID, public IP, DNS and website URL
- validation and review before every apply
- documented defect management and test evidence

## 3. Defect management

The DMC workflow contains an original script, a corrected working version and
verification evidence.

Defects DMC-001 through DMC-033 covered areas such as:

- unsafe or destructive automation
- incorrect commands and paths
- missing validation
- misleading comments
- quoting and syntax problems
- non-portable configuration
- unsafe Terraform execution
- missing error handling
- outdated terminal output embedded in scripts

The corrected script and its evidence are stored under `DMC/`.

## 4. Level 4 Iteration 1

Level 4 Iteration 1 rebuilt the supplied automation as a safer local workflow.

Important improvements include:

- strict Bash error handling
- predictable project-directory resolution
- required command and file checks
- AWS result validation
- subnet and VPC consistency checks
- AMI availability validation
- SSH key and AWS key-pair checks
- automatic public-IP detection
- preservation of the original tfvars file
- protection against overwriting an existing plan
- non-interactive Terraform initialization
- Terraform formatting and validation
- creation of a reviewable saved plan
- manual apply after explicit review
- removal of automatic destroy, blocking SSH and stale verification commands

## 5. Deployment result

Terraform replaced the stopped legacy EC2 instance with a new instance using
the reviewed configuration.

Verification confirmed:

- the EC2 instance entered the running state
- the instance received a public IP and DNS name
- the expected subnet and security groups were attached
- Nginx started successfully
- the application was cloned from GitHub
- the expected `Hey me!` HTML page was served
- the HTTP endpoint returned the expected content
- a post-apply Terraform plan reported no remaining changes

No live infrastructure identifiers or credentials are included in this report.

## 6. Security measures

The repository excludes:

- Terraform state files
- tfvars and tfvars backups
- saved Terraform plans
- private keys
- local Terraform directories
- editor and operating-system files
- temporary repair and backup scripts

Additional controls include:

- IMDSv2 requirement
- SSH restricted to a single configurable CIDR
- public access limited to HTTP
- encrypted root storage
- Git secret-pattern scanning
- portable paths instead of personal workstation paths
- manual review before destructive changes

## 7. Validation

The final delivery passed:

- `terraform fmt -check`
- `terraform validate`
- Bash syntax validation
- Git staged-diff validation
- sensitive filename checks
- credential and private-key pattern checks
- live HTTP content verification
- post-apply Terraform drift detection

## 8. Limitations

This is an educational environment. The current solution still has areas that
would need improvement before production use:

- HTTP is used instead of HTTPS
- Terraform state is stored locally
- the application repository is not pinned to an immutable commit
- no automated CI workflow is included yet
- no load balancer, autoscaling or multi-AZ architecture is used
- monitoring, alerting and automated cost controls are limited

## 9. Conclusion

The project demonstrates a complete DevOps workflow: infrastructure as code,
defect analysis, safe automation, configuration management, deployment,
verification, security review and version control.

The final environment is reproducible, validated and appropriate for its
school and APL purpose.
