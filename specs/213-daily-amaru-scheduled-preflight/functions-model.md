# Functions model — Issue 213

Artifact ceiling: 4,000 bytes and 100 lines.

This file defines only changed interface signatures and constraints. Shell
values are UTF-8 strings unless a stricter type is named.

| ID | Interface | Arguments | Result / effects | Constraints |
|---|---|---|---|---|
| FN-213-01 | `write_receipt` | `stage: Stage`, `outcome: Outcome`, `fields: ReceiptField[]` | `Status`; refreshes D213-01 and requests external publication | Local D213-01 must exist before transport publication is attempted |
| FN-213-02 | `fail_stage` | `stage: Stage`, `error: ErrorCode` | Non-zero termination after FN-213-01 | Error is specific; failure cannot become unchanged/changed/success |
| FN-213-03 | transport `preflight` operation | `requirements: CommandName[]` | Success with D213-04 evidence, or non-zero missing-command result | No claim, mutation, integration, or launch effect |
| FN-213-04 | transport `receipt` operation | `fields: ReceiptField[]` | External receipt publication status | Minimum dependency surface; must not require the command whose absence it reports when an independent sink remains available |
| FN-213-05 | `with_identity` | `identity: SecretToken`, `command: Command`, `arguments: String[]` | Command status and output | Token is process-environment-only and never printed or persisted |
| FN-213-06 | transport `prepare-consumer-repin` operation | `image_ref: ImageRef` | Exact consumer candidate SHA | Uses the cna repository token, never D213-03 |

`Stage` includes distinct scheduled dependency preflight and production
identity values. `ErrorCode` distinguishes at least the missing command name
and missing production identity. Existing transport operation signatures not
listed here remain unchanged.
