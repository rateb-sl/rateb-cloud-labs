#!/usr/bin/env bash
# Create, inspect, checksum, and record a gzip-compressed tar archive.
# Usage: ./backup-archive.sh SOURCE_DIRECTORY BACKUP_DIRECTORY

set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf 'Usage: %s SOURCE_DIRECTORY BACKUP_DIRECTORY\n' "$0" >&2
  exit 64
fi

source_dir=$(cd "$1" && pwd -P)
backup_dir=$2

if [[ ! -d "$source_dir" ]]; then
  printf 'Source directory does not exist: %s\n' "$source_dir" >&2
  exit 66
fi

mkdir -p "$backup_dir"
backup_dir=$(cd "$backup_dir" && pwd -P)

case "$backup_dir/" in
  "$source_dir/"*)
    printf 'Backup directory must not be inside the source directory.\n' >&2
    exit 65
    ;;
esac

source_name=$(basename "$source_dir")
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
archive="$backup_dir/${source_name}-${timestamp}.tar.gz"
checksum_file="${archive}.sha256"
audit_log="$backup_dir/backup-audit.csv"

if command -v sha256sum >/dev/null 2>&1; then
  checksum_command=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  checksum_command=(shasum -a 256)
else
  printf 'A SHA-256 tool (sha256sum or shasum) is required.\n' >&2
  exit 69
fi

printf 'Creating archive: %s\n' "$archive"
tar -C "$(dirname "$source_dir")" -czf "$archive" "$source_name"

printf 'Inspecting archive contents:\n'
tar -tzf "$archive"

"${checksum_command[@]}" "$archive" > "$checksum_file"
printf '%s,%s,%s,%s\n' \
  "$timestamp" "$source_dir" "$archive" "$(awk '{print $1}' "$checksum_file")" \
  >> "$audit_log"

printf '\nVerification files created:\n'
printf 'Archive:    %s\n' "$archive"
printf 'Checksum:   %s\n' "$checksum_file"
printf 'Audit log:  %s\n' "$audit_log"
printf '\nNext check: sha256sum -c %q\n' "$checksum_file"
