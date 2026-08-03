#!/bin/bash
# Creates the next 25 numbered empty files in a directory.
# Each run continues from the highest number already present,
# so there are no hard-coded starting numbers.
#
# Usage: ./numbered-files.sh [directory]
set -euo pipefail

dir="${1:-.}"
mkdir -p "$dir"

highest=0
for f in "$dir"/*; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  if [[ "$base" =~ ^[0-9]+$ ]]; then
    n=$((10#$base))
    if (( n > highest )); then
      highest=$n
    fi
  fi
done

start=$((highest + 1))
end=$((start + 24))

for n in $(seq "$start" "$end"); do
  touch "$dir/$n"
done

echo "Created files $start through $end in $dir"
