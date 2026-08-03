# Walkthrough: Systems Manager Patch Manager

Guided walkthrough based on an AWS Training sandbox lab. Expected evidence is labeled as expected, not observed. Run this in a training sandbox or disposable account.

## Goal

Use AWS Systems Manager Patch Manager to define a patch baseline, scan managed nodes for compliance, and run a patch operation, then read the compliance report correctly.

## Steps

1. Open Systems Manager, then Patch Manager.
2. Review the default patch baseline for the operating system of your nodes (Amazon Linux, Ubuntu, etc.). A baseline defines which patches are approved and how urgency is handled.
3. Confirm your EC2 instances appear as managed nodes (they need the SSM Agent and an IAM instance profile that allows Systems Manager actions).
4. Run a compliance scan and open the compliance report.
5. Run a patch operation against one node and re-check its compliance state.
6. Record what changed and what the report says afterward.

## Expected evidence (verify against your own run)

- Managed nodes listed with their current patch compliance state.
- A compliance report showing how many patches are missing per node against the assigned baseline.
- After patching, the node's compliance state moves toward Compliant.

## Evidence boundaries

- Patch compliance is evidence relative to a baseline. It does not certify the node as secure, and it says nothing about application-level vulnerabilities.
- "Compliant" can change when the baseline changes, not only when patches are installed.
- A node missing from the list is usually an SSM Agent or instance-profile problem, not a patch problem.

## What this teaches

- Patching is a policy question first: who decides what is approved, and what is the evidence of compliance?
- A compliance dashboard is a measurement, not a health certificate.
