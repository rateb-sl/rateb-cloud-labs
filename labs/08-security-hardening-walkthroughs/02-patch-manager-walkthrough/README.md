# Systems Manager Patch Manager: baseline, compliance, re-check

## Goal

Use this walkthrough to evaluate a managed node against a patch baseline, apply the smallest required change, and verify compliance against the same baseline.

## Control model

```text
managed node
  → patch baseline
  → compliance assessment
  → approved patch operation
  → compliance read-back
```

Compliance means “matches this baseline.” It is not a complete security verdict.

## Implementation

1. Confirm the Region, managed-node registration, and baseline ownership.
2. Read the baseline rules and identify the missing or non-compliant patches.
3. Run the patch operation only against the intended node and baseline.
4. Read the command invocation and compliance state back.
5. Confirm the node's state changed for the intended reason.

## Evidence boundaries

- A node registered in Systems Manager is not automatically compliant.
- A successful command request is not proof that the patch completed.
- Compliance against one baseline does not prove the host is secure in every dimension.

## Cleanup

Remove only disposable test nodes, associations, or schedules created for the walkthrough. Preserve shared baselines and production maintenance windows.
