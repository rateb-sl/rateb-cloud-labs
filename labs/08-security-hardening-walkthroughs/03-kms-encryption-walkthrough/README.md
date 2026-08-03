# Walkthrough: data protection with AWS KMS encryption

Guided walkthrough based on an AWS Training sandbox lab. Expected evidence is labeled as expected, not observed. Run this in a training sandbox or disposable account.

## Goal

Use AWS KMS to create a symmetric key, then use the AWS Encryption CLI to encrypt a file, decrypt it, and see why the key is the asset while the CLI is only the tool.

## Steps

1. Open the KMS service and create one symmetric key (`MyKMSKey`).
2. Note the two roles in the key policy:
   - Key administrators: manage the key (rotation, deletion, policy). They do not automatically get to use the key for encryption.
   - Key users: can use the key for cryptographic operations (encrypt/decrypt) but cannot administer it.
3. On an EC2 instance with the AWS Encryption CLI installed, write a plaintext file.
4. Encrypt the file with the key:

```bash
aws-encryption-cli --encrypt \
  --input plaintext.txt --output encrypted.out \
  --wrapping-keys key="<key-id>" \
  --metadata-output metadata.json
```

5. Confirm the output is ciphertext (binary, not readable text).
6. Decrypt it back:

```bash
aws-encryption-cli --decrypt \
  --input encrypted.out --output decrypted.txt \
  --wrapping-keys key="<key-id>" \
  --metadata-output metadata.json
```

7. Compare `decrypted.txt` to the original.

## Expected evidence (verify against your own run)

- A symmetric KMS key exists with separate administrator and user policies.
- The encrypted file is not readable as text; the decrypted file matches the original byte for byte.
- Attempting to decrypt without the key (or as a principal without key-user permission) fails.

## Evidence boundaries

- Encryption protects data at rest and in transit mechanics; it does not fix access control on the surrounding systems.
- A key that can decrypt is valuable. Restrict who can use it and rotate it on a schedule.
- Never store access keys, secret keys, or session tokens in scripts, repositories, or screenshots.

## Cleanup

Delete the test key after the lab (or schedule deletion) and remove the test files. Keys are regional and cost nothing while unused, but the habit of cleanup matters.

## What this teaches

- Encryption is a reversible transformation controlled by a key. The key is the asset; the tool only carries out the operation.
- Separating key administrators from key users is the same least-privilege idea as IAM groups: the ability to manage a thing is different from the ability to use it.
