# Bash scripting challenge: continuing numbered files

## Goal

Write a Bash script that creates 25 empty numbered files (`1` to `25`). On every later run it must create the next 25 numbers (`26` to `50`, then `51` to `75`) without any hard-coded starting number.

This is a small automation task that forces the useful habits: inspect the current state before changing it, handle the empty case, and make the script idempotent.

## The solution

[`scripts/numbered-files.sh`](scripts/numbered-files.sh):

1. Scans the target directory for existing files whose names are pure numbers.
2. Finds the highest number (defaulting to 0 when none exist).
3. Creates the next 25 numbers after it.

```bash
chmod u+x scripts/numbered-files.sh

./scripts/numbered-files.sh /tmp/lab-dir
# Created files 1 through 25 in /tmp/lab-dir

./scripts/numbered-files.sh /tmp/lab-dir
# Created files 26 through 50 in /tmp/lab-dir
```

## Why it is written this way

- `set -euo pipefail` stops the script on unset variables and failed commands instead of silently continuing.
- The `10#$base` prefix forces base-10 arithmetic, so a filename like `08` is not treated as invalid octal.
- `mkdir -p` makes the directory if it does not exist, so the first run works in a fresh path.
- Counting from the highest existing number instead of tracking a counter file means the script cannot drift if a file is deleted.

## Verification

```bash
ls /tmp/lab-dir | sort -n | head -3   # 1
ls /tmp/lab-dir | sort -n | tail -3   # 23 24 25
ls /tmp/lab-dir | wc -l               # 25
```

Run it a second time and confirm the count is 50 and the highest file is 50.

## Variations to try

- Create files with an extension (`01.log`, `02.log`, ...) and adapt the number extraction.
- Refuse to overwrite: fail with a message if a target file already exists.
- Accept a start offset as an optional second argument for testing.
