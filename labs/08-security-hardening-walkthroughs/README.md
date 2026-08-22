# AWS security hardening walkthroughs: assess, remediate, verify

## Goal

This folder contains three AWS Training walkthroughs. They are implementation guides, not claims of completed production work:

| Walkthrough | Control path |
|---|---|
| [01. Amazon Inspector](01-inspector-walkthrough/README.md) | Activate scanning, interpret a vulnerability finding, remediate, redeploy, verify |
| [02. Patch Manager](02-patch-manager-walkthrough/README.md) | Patch baseline, managed node, compliance state |
| [03. KMS encryption](03-kms-encryption-walkthrough/README.md) | Symmetric key, key administrators/users, encrypt/decrypt round trip |

## Common operating model

```text
establish baseline
  → inspect finding or compliance state
  → change the smallest relevant control
  → re-check the same evidence layer
  → record the remaining boundary
```

A patch-compliance result means compliance with a particular baseline, not that the host is secure in every dimension. An Inspector finding is a triage signal, not proof of compromise. A successful encryption command is not enough unless the decrypted output matches the original and the key policy is understood.

## Implementation

1. Confirm the assigned sandbox/account, Region, and starting resources.
2. Read the walkthrough's task contract and identify the baseline evidence.
3. Apply only the control required by the scenario.
4. Read the same service state back after the change.
5. Record expected versus observed results and end the lab.

## Cleanup

Run these walkthroughs only in a training sandbox or disposable account. Do not place credentials, private keys, meeting links, or raw sandbox identifiers in a public repository. Remove temporary keys, roles, nodes, findings fixtures, and KMS material only when ownership is confirmed; do not delete shared security resources.
