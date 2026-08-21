# Functions model — Issue 229

Artifact ceiling: 2,000 bytes and 50 lines.

No new public command is introduced.

## F229-1 — transport operation `require-bootstrap-checks`

- Argument: `candidate: 40-hex bootstrap head`.
- Environment: existing repository/identity/check-set fields plus bounded
  observation inputs required by D229-2.
- Result: observed check rows on exact all-success; non-zero named D229-3
  outcome otherwise.
- Effects: read-only GitHub observations and bounded clock/sleep effects.
- Changed constraint: one immediate census is insufficient to classify an
  incomplete or absent check as terminal.

## F229-2 — Actions observation helper(s)

- Arguments: `target_repository`, `candidate`, `identity` and any explicit
  check/window inputs selected by the commit owner.
- Result: D229-1 lifecycle rows plus D229-2 duration provenance, or a retryable
  transport error.
- Effects: read-only API access only.
- Constraint: existing consumer-check callers retain their current behavior;
  bootstrap retry state must not silently alter their contract.
