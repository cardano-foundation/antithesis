# Functions model — Issue 232

Artifact ceiling: 2,500 bytes and 65 lines.

No internal helper signature is mandated.

## F232-1 — executable `scripts/daily-amaru-watchdog.sh`

- Arguments: none in scheduled production; proof inputs are explicit and
  accepted only in proof mode.
- Environment: repository identity, GitHub token, workflow revision/run URL,
  evidence path, fixed receipt issue, and an injectable clock/GitHub boundary
  available only outside production.
- Result: one D232-3 verdict and a D232-5 evidence record.
- Effects: complete receipt-comment reads; on `ABSENT`, minimal issue
  list/create/comment operations; on `PRESENT`, no issue creation and at most
  a non-closing recovery note on the existing open incident.
- Constraints: production derives D232-1 itself, consumes no producer-run
  surface, and emits evidence before its exit status.

## F232-2 — watchdog workflow invocation

- Scheduled input: none.
- Manual input: proof-only selector with no production source/day authority.
- Result: uploaded D232-5 artifact on success or failure and a workflow status
  matching the inner verdict/control contract.
- Effects: production uses repository issue read/write permissions; proof mode
  has no external GitHub write and accounts for all synthetic effects.

## F232-3 — focused test entry `just test-daily-amaru-watchdog`

- Arguments: none.
- Result: zero only after every invariant control passes; counted output names
  `WATCHDOG-NEGATIVE`, `WATCHDOG-REPEAT`, `WATCHDOG-POSITIVE`, and
  `WATCHDOG-NO-RUN`.
- Effects: temporary local state only; zero network, credentials, real issues,
  producer runs, receipts, or alarm mutations.
