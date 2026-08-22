# Amazon Inspector: assess, remediate, verify

## Scope

Use this walkthrough to activate vulnerability assessment, interpret a package finding, apply the smallest remediation, and verify the same finding state again.

## Control model

```text
resource inventory
  → Inspector assessment
  → finding triage
  → targeted remediation
  → redeploy or rescan
  → finding-state verification
```

A finding is a signal requiring triage. It is not proof of compromise, and coverage is not the same as security.

## Implementation and verification

1. Confirm the account, Region, target resource, and Inspector coverage state.
2. Read the finding's resource, package, CVE, severity, and remediation guidance.
3. Apply only the remediation that addresses the identified package or configuration.
4. Redeploy or rescan as required by the sandbox.
5. Read the same finding back and confirm its state and scan timestamp.

## Evidence boundaries

- Coverage proves the resource is being assessed, not that it is secure.
- A finding proves an assessment result, not exploitation.
- A closed finding proves the specific finding was re-evaluated, not that all risk is gone.

## Cleanup

Deactivate or remove only the disposable resources created for the walkthrough. Do not change shared Inspector configuration without confirming ownership.
