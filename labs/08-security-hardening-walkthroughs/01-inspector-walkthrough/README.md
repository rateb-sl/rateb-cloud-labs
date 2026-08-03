# Walkthrough: Amazon Inspector vulnerability assessment

Guided walkthrough based on an AWS Training sandbox lab. Expected evidence is labeled as expected, not observed. Run this in a training sandbox or disposable account.

## Goal

Close the security loop behind Amazon Inspector: activate a scan, see what is covered, read a package vulnerability finding, make the smallest dependency change, redeploy, and confirm the finding is no longer active.

## Steps

1. Open the Inspector service and activate the scans the account supports (EC2 and Lambda standard scanning).
2. Confirm coverage: which resources are enabled for scanning and in which Region.
3. Wait for an initial scan, then open Findings.
4. Pick one package vulnerability finding and read it like a ticket:
   - Which package and version are affected?
   - Which CVE is referenced?
   - What is the recommended remediation (usually a dependency version bump)?
5. Apply the smallest fix the finding recommends in the application code or dependency manifest.
6. Redeploy the affected resource.
7. Re-open the finding and confirm it moves out of the active state after the next scan.

## Expected evidence (verify against your own run)

- Inspector shows enabled scans and a coverage list for the account and Region.
- A finding lists the affected package, the CVE, and a remediation path.
- After the fix and redeploy, the finding is no longer listed as active.

## Evidence boundaries

- A clean Inspector scan covers the resources in scope at scan time. It is not a guarantee about code you wrote or resources not in scope.
- A finding that disappears proves the condition was remediated; it does not prove the application is free of other issues.

## Cleanup

Disable or deactivate Inspector scans if the sandbox does not do it, so the account does not keep scanning paid resources.

## What this teaches

- Vulnerability management is a loop: scan, interpret, fix, redeploy, re-scan.
- The interpretation step is the actual skill. A CVE number means nothing until you know whether the affected package is in your deployed artifact and how it is used.
