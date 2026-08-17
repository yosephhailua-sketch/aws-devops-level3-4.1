# Security Policy

## Educational scope

This repository is a school and APL project. It demonstrates AWS, Terraform,
Bash, Ansible and DevOps concepts and is not presented as a production-ready
reference architecture.

## Reporting a vulnerability

Do not publish suspected credentials, tokens or private infrastructure details
in a public issue.

Use GitHub's private vulnerability reporting or Security Advisory function if
it is enabled for the repository. Otherwise, contact the repository owner
privately through their GitHub profile.

## Repository secret policy

The following content must never be committed:

- AWS access keys or session tokens
- GitHub personal access tokens
- passwords
- private SSH keys
- Terraform state files
- tfvars files containing environment-specific values
- saved Terraform plans
- cloud credentials or local credential files

If a secret is committed, removing it in a later commit is insufficient. The
secret must be revoked or rotated and removed from the complete Git history.

## Infrastructure identifiers

Examples should use variables or documentation-safe placeholders where
possible. Active public IP addresses, account identifiers and unnecessary
resource identifiers should not be published.

## Supported version

Only the latest version of the `main` branch is maintained.
