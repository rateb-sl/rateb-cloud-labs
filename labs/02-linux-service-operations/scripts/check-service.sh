#!/usr/bin/env bash
# Report systemd service state and optionally test a local HTTP endpoint.
# Usage: ./check-service.sh SERVICE_NAME [URL]

set -euo pipefail

service_name=${1:-httpd}
url=${2:-}

if ! command -v systemctl >/dev/null 2>&1; then
  printf 'systemctl is required; run this on a systemd-based Linux host.\n' >&2
  exit 69
fi

printf 'Service: %s\n' "$service_name"
printf 'Active:  '
systemctl is-active "$service_name" || true
printf 'Enabled: '
systemctl is-enabled "$service_name" || true

if [[ -n "$url" ]]; then
  if ! command -v curl >/dev/null 2>&1; then
    printf 'curl is not installed; skipping endpoint check for %s\n' "$url" >&2
    exit 0
  fi

  printf 'HTTP check: %s\n' "$url"
  curl --fail --silent --show-error --head --max-time 5 "$url" >/dev/null
  printf 'Endpoint responded successfully.\n'
fi
