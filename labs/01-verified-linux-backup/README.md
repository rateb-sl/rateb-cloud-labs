# Verified Linux backup workflow

## Goal

Create a compressed archive of a directory, prove what went into it, record an integrity checksum, and test that it can be extracted. The goal is not to call a `.tar.gz` file a backup and move on. It is to leave enough evidence that I can trust the archive later.

## Environment

- Linux shell
- `tar`, `sha256sum`, `find`, and standard POSIX utilities
- A disposable source directory and a separate backup destination

## What I built

[`scripts/backup-archive.sh`](scripts/backup-archive.sh) creates a timestamped `.tar.gz` archive from a source directory. It then:

1. lists the archive contents without extracting it;
2. calculates a SHA-256 checksum;
3. writes a small CSV audit log; and
4. prints the paths needed for verification.

The script takes absolute or relative paths, but I prefer absolute paths in operational runbooks so the target is obvious.

```bash
chmod u+x scripts/backup-archive.sh
./scripts/backup-archive.sh /srv/example-app /var/backups/example-app
```

## Verification

```bash
# Inspect the archived paths without changing the filesystem.
tar -tzf /var/backups/example-app/example-app-YYYYMMDDTHHMMSSZ.tar.gz

# Recalculate and compare against the recorded checksum.
sha256sum -c /var/backups/example-app/example-app-YYYYMMDDTHHMMSSZ.tar.gz.sha256

# Test a restore into an empty disposable directory.
mkdir -p /tmp/restore-test
tar -xzf /var/backups/example-app/example-app-YYYYMMDDTHHMMSSZ.tar.gz -C /tmp/restore-test
find /tmp/restore-test -maxdepth 2 -print
```

A matching checksum proves that the archive bytes match the checksum file. The restore test proves that the archive is readable. Neither check replaces a real retention, off-host-copy, or recovery policy.

## Troubleshooting notes

- If `tar` exits with an error, stop before moving or deleting anything. Read the error and inspect the source path.
- If the backup destination is inside the source tree, the archive can include itself. The script blocks that layout.
- `tee` overwrites by default. Use `tee -a` when appending an operational log.
- `df -h` shows free capacity by mounted filesystem; `du -sh <path>` shows the size of a particular directory tree.

## What I learned

The useful pattern is:

```text
inspect → archive → list contents → checksum → restore test → retain evidence
```

A file that merely exists is not enough. I need to know what it contains, whether it can be read, and where I would restore it.

## Security and cleanup

- Do not archive credentials, private keys, or files you are not authorized to copy.
- Review ownership and permissions on the backup destination.
- Remove `/tmp/restore-test` after a successful disposable test.
- For production, add encryption, retention, monitoring, and an off-host copy. This lab intentionally stays focused on the first safe workflow.
