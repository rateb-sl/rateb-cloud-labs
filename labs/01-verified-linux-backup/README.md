# Verified Linux backup workflow: archive, prove, restore

## Goal

Create a compressed archive, prove what it contains, record an integrity checksum, and test that it can be restored. A `.tar.gz` file is not a trustworthy backup until its contents and recovery path have been checked.

## Environment

- Linux shell
- `tar`, `sha256sum`, `find`, and standard POSIX utilities
- Disposable source directory
- Separate backup destination

## Operating model

```text
source directory
  → archive
  → archive inventory
  → checksum record
  → isolated restore test
  → retained evidence
```

Each stage answers a different question:

| Question | Evidence |
|---|---|
| Did an archive get created? | Archive path and size |
| What is inside it? | `tar -tzf` listing |
| Did the bytes change? | SHA-256 verification |
| Can it be recovered? | Extraction into an empty directory |

A checksum proves byte identity. It does not prove that the source was complete or that the backup is stored off-host.

## Implementation

### 1. Create the archive

[`scripts/backup-archive.sh`](scripts/backup-archive.sh) accepts a source and destination, rejects unsafe layouts such as a destination inside the source tree, creates a timestamped archive, and records the resulting paths.

```bash
chmod u+x scripts/backup-archive.sh
./scripts/backup-archive.sh /srv/example-app /var/backups/example-app
```

The important design choice is that the script derives its inputs from the filesystem rather than relying on a manually typed archive name.

### 2. Inspect the archive

```bash
tar -tzf /var/backups/example-app/example-app-YYYYMMDDTHHMMSSZ.tar.gz
```

This is a read-only check. It proves the archive can be read and shows the paths captured, but it does not modify or restore the filesystem.

### 3. Verify integrity

```bash
sha256sum -c /var/backups/example-app/example-app-YYYYMMDDTHHMMSSZ.tar.gz.sha256
```

A matching checksum proves that the archive bytes match the recorded checksum file. It does not prove the original source was correct.

### 4. Test recovery

```bash
mkdir -p ./restore-test
tar -xzf /var/backups/example-app/example-app-YYYYMMDDTHHMMSSZ.tar.gz -C ./restore-test
find ./restore-test -maxdepth 2 -print
```

Restoring into an empty disposable directory tests readability without overwriting the original source.

## Failure boundaries

- If `tar` fails, stop before moving or deleting anything.
- A backup destination inside the source tree can cause the archive to include itself.
- `df -h` reports filesystem capacity; `du -sh <path>` reports directory size.
- `tee` overwrites by default; use `tee -a` when appending an audit log.

## Verification

The complete proof is:

```text
inspect → archive → list → checksum → isolated restore → retain evidence
```

## Cleanup

- Do not archive credentials, private keys, or unauthorized data.
- Review ownership and permissions on the backup destination.
- Remove `./restore-test` after the test.
- Production backups need encryption, retention, off-host copies, monitoring, and a tested recovery objective.
