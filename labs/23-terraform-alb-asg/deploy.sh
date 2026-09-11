#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
ACTION="${2:-plan}"
TFVARS_FILE="environments/${ENVIRONMENT}/terraform.tfvars"

if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
  printf 'Error: environment must be dev, staging, or prod.\n' >&2
  exit 1
fi

if [[ ! "$ACTION" =~ ^(plan|apply|destroy)$ ]]; then
  printf 'Error: action must be plan, apply, or destroy.\n' >&2
  exit 1
fi

if [[ ! -f "$TFVARS_FILE" ]]; then
  printf 'Error: missing %s\n' "$TFVARS_FILE" >&2
  exit 1
fi

case "$ACTION" in
  plan)
    terraform plan -var-file="$TFVARS_FILE"
    ;;
  apply)
    terraform plan -var-file="$TFVARS_FILE" -out=tfplan
    printf 'Apply the reviewed plan? Type yes: '
    read -r confirmation
    if [[ "$confirmation" == "yes" ]]; then
      terraform apply tfplan
    else
      printf 'Apply cancelled.\n'
      rm -f tfplan
    fi
    ;;
  destroy)
    printf 'This destroys Terraform-managed %s infrastructure. Type destroy: ' "$ENVIRONMENT"
    read -r confirmation
    if [[ "$confirmation" == "destroy" ]]; then
      terraform destroy -var-file="$TFVARS_FILE"
    else
      printf 'Destroy cancelled.\n'
    fi
    ;;
esac
