# AWS security hardening walkthroughs

## Goal

Three guided walkthroughs from my AWS security training track: vulnerability assessment with Amazon Inspector, patch compliance with Systems Manager Patch Manager, and data protection with AWS KMS encryption.

Important honesty note: these are guided walkthroughs written from AWS Training sandbox labs. They are not records of completed production work. Where a result is shown, it is labeled as expected evidence, not observed output. Run them in a training sandbox or a disposable account to generate your own evidence.

| Walkthrough | What it demonstrates |
|---|---|
| [01. Amazon Inspector](01-inspector-walkthrough/README.md) | Activate scanning, interpret a package vulnerability finding, remediate, redeploy, verify |
| [02. Patch Manager](02-patch-manager-walkthrough/README.md) | Patch baselines, managed nodes, compliance reporting |
| [03. KMS encryption](03-kms-encryption-walkthrough/README.md) | Symmetric keys, key administrators vs key users, AWS Encryption CLI |

## Shared principles

- Evidence is relative to a baseline. A patch compliance number means "compliant with this baseline," not "secure."
- A finding is a signal that deserves triage, not a verdict.
- Make the smallest change that addresses the finding, then re-check the same evidence layer.
