#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-list}"

case "$ACTION" in
  list)
    terraform state list
    ;;
  show)
    if [[ -z "${2:-}" ]]; then
      printf 'Usage: ./state.sh show RESOURCE_ADDRESS\n' >&2
      exit 1
    fi
    terraform state show "$2"
    ;;
  pull)
    terraform state pull
    ;;
  *)
    printf '%s\n' 'Usage: ./state.sh [list|show RESOURCE_ADDRESS|pull]' >&2
    exit 1
    ;;
esac
