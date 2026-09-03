# Plan — Issue 232 independent daily receipt watchdog

Artifact ceiling: 6,500 bytes and 150 lines.

## Technical context

The canonical receipt source is paginated comments on cna#210. Current
production evidence shows dated receipt comments on every observation day,
including failed stages. This ticket detects only the stronger absence class:
the producer never reached any receipt boundary. GitHub comment `created_at`
anchors the receipt to the claimed UTC day without depending on producer-run
state.

## Architecture decisions

- A new executable owns day derivation, receipt observation, verdict evidence,
  and alarm reconciliation. Its GitHub operations are an injected boundary so
  deterministic tests run with no network, credentials, or external writes.
- A new workflow owns a cron later than the producer and evaluates the previous
  UTC day, so the complete day is closed regardless of when the producer was
  due or whether its workflow existed. It grants only the read/write permissions
  needed for receipt observation and incident reconciliation.
- Production accepts no observation-day override. Test clock/source injection
  is explicit and rejected in production mode.
- The incident is discovered by a stable body marker and reconciled under the
  workflow's own non-cancelling concurrency group. History keys are observation
  dates, making retries idempotent while retaining distinct missing days.
- `PRESENT`, `ABSENT`, and boundary `ERROR` remain distinct. The script emits
  evidence before returning the corresponding status; the workflow uploads it
  even when the verdict is red.
- Manual dispatch is proof-only. It runs the same decision/reconciliation path
  over deterministic synthetic state and uploads the red/green receipt; it has
  no authority to alter the production source or choose a production day.

## Slice

One bisect-safe **OWNER** slice, `S232-01`. Persistent incident reconciliation,
GitHub pagination, workflow permissions, and recovery lifetime rules require
semantic review and are not eligible for LIGHT.

The commit owner first commits the complete executable RED proof, then lands
the workflow, script, fixtures, and permanent controls together. No draft tool
is authorized because the owned path includes a GitHub-token permission and
external-write boundary.

## Proof strategy

- Drive the real watchdog executable through a hermetic fake GitHub command
  that records reads, pages, issue creation, comments, and close attempts.
- Seed missing, repeated-missing, restored-present, wrong-marker/day/time,
  multi-page, malformed, read-failure, and write-failure states.
- Derive observation days around month/year and midnight boundaries from an
  injected clock; reject any production day/source override.
- Count open marked incidents and per-day history rows after each transition.
- Apply verified workflow/script/test mutants proving the schedule caller,
  independent workflow, red exit, timestamp filter, pagination, and positive
  leg are all reachable from `just ci`.
- Emit secret-shaped fixture values and verify public artifacts contain only
  stable safe IDs and exact revision/day/verdict fields.

## Verification envelope

- Frozen untracked `./gate.sh` plus its runtime backup and SHA-256 identity.
- `just test-daily-amaru-watchdog`, workflow validation, shell analysis,
  formatting, and complete `nix develop --quiet -c just ci`.
- Exact changed-path census and proof that all existing producer files are
  byte-identical to the frozen base.
- Fresh independent audit of the exact candidate, then final tree/commit/gate
  receipts before push.
- Required hosted contexts plus a post-merge proof-only workflow run whose
  artifact contains both alarm and green evidence on the exact merged head.

## Stop conditions

Stop and ask before changing the producer, receipt format/source issue,
production day override policy, cna#202, credentials, launcher/preflight/image
contracts, or property/run-correlation semantics; before auto-closing an
incident; or before publishing synthetic receipts into the production source.
