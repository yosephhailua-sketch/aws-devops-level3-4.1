#!/usr/bin/env bash
set -euo pipefail

DNS=$(terraform output -raw ec2_public_dns_name)
RESPONSE=$(curl -fsS --max-time 10 "http://${DNS}")

if grep -q 'Hey me!' <<< "$RESPONSE"; then
  echo "SUCCESS: Website is reachable and displays 'Hey me!'"
else
  echo "ERROR: Expected website content was not found." >&2
  exit 1
fi
