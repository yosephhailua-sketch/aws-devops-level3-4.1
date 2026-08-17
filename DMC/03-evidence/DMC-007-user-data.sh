#!/bin/bash
###########################################################
# Perform configuration management
###########################################################
# - detect Amazon Linux version
if [[ ! -r /etc/os-release ]]; then
  printf 'ERROR: /etc/os-release kunde inte lÃ¤sas.\n' >&2
  exit 1
fi

. /etc/os-release

if [[ "${ID:-}" != "amzn" ]]; then
  printf 'ERROR: Operativsystemet stÃ¶ds inte: %s\n' "${ID:-unknown}" >&2
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
    printf 'ERROR: Amazon Linux-versionen stÃ¶ds inte: %s\n' \
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
