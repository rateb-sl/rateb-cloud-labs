# KMS encryption: key policy, encrypt, decrypt, verify

## Scope

Use this walkthrough to create or identify a symmetric KMS key, separate key-administrator and key-user responsibilities, and prove an encryption/decryption round trip.

## Control model

```text
plaintext
  → encryption context + KMS key policy
  → ciphertext
  → matching key permissions and context
  → plaintext
```

Encryption is reversible transformation controlled by key permissions. The encryption context is authenticated metadata; it is not a secret and must match during decrypt.

## Implementation

1. Confirm the account, Region, key ownership, and intended disposable input.
2. Read the key policy and distinguish administrators from users who may encrypt/decrypt.
3. Encrypt the test input with the AWS Encryption CLI or supported API.
4. Check the command result and confirm ciphertext differs from plaintext.
5. Decrypt using the same key and matching encryption context.
6. Compare the recovered plaintext with the original bytes.

A zero exit code only proves the command ran; the round-trip comparison proves the data result.

## Evidence boundaries

- Key existence does not prove a caller can use it.
- Encrypt success does not prove decrypt success.
- Matching decrypted bytes prove the round trip, not a production key-rotation or backup strategy.

## Cleanup

Delete only disposable KMS keys after the required waiting/recovery policy is understood. Remove temporary ciphertext and plaintext files. Never delete a shared production key.
