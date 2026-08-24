# Independent Daily Amaru receipt watchdog

Issue: cardano-foundation/cardano-node-antithesis#232 · parent epic #205
Frozen main base: `64024b9dfe73e552ae621526829074d74d484f7c`

Artifact ceiling: 9,000 bytes and 210 lines.

## Context

The producer is `.github/workflows/daily-amaru.yaml`, scheduled at 04:17 UTC.
Its GitHub transport publishes receipt comments to cna#210. A current receipt
starts with `<!-- daily-amaru receipt -->`, carries an exact `day=YYYY-MM-DD`
field, and has GitHub-owned `created_at` metadata. The producer may publish
several stage receipts and may end in failure; for this ticket, any authentic
receipt proves only that the producer reached its receipt boundary. Property
completeness and run correlation remain cna#206/cna#207.

## Requirements

- **R232-1 — independent reachability.** A workflow distinct from
  `daily-amaru.yaml` owns its own schedule and invokes the watchdog directly.
  It remains reachable when the producer has no workflow run at all.
- **R232-2 — independent UTC decision.** A scheduled invocation derives the
  previous UTC observation day and its closed UTC interval from its own clock.
  It does not consume a producer output, run, artifact, or supplied day.
- **R232-3 — canonical presence.** `PRESENT` requires at least one paginated
  cna#210 issue comment with the exact receipt marker, the exact observation
  day field, and a GitHub creation timestamp inside that UTC day. Receipt
  outcome, property data, run ID, digest, and producer workflow status do not
  participate in this ticket's verdict.
- **R232-4 — absence alarms.** After the observation day is closed, zero
  matching receipts yields `ABSENT`, reconciles the canonical open incident,
  writes durable evidence, and exits non-zero. API, pagination, parse, clock,
  or reconciliation failure is a distinct fail-closed error, never `PRESENT`
  or a fabricated absence.
- **R232-5 — one incident, durable history.** The alarm is identified by a
  stable machine marker rather than title search alone. First absence opens
  it; later absent days and same-day repeats update that one open incident
  idempotently, preserving one history entry per observation day and stable
  links without duplicating open incidents.
- **R232-6 — reviewed recovery.** `PRESENT` emits an observable green verdict.
  If the canonical incident is still open, recovery may be recorded there but
  automation never closes it; no present day creates a new alarm.
- **R232-7 — public-safe evidence.** Verdict evidence names the observation
  day, receipt count or zero, stable comment/issue/run identities, and action,
  while excluding tokens, authorization headers, signed URLs, and comment
  bodies that could contain unrelated data.
- **R232-8 — permanent able-to-fail proof.** The deterministic suite omits a
  synthetic day's receipt and observes non-zero plus incident creation, repeats
  absence and observes one updated incident with preserved history, restores a
  valid receipt and observes green without closure, and proves the same absent
  verdict with no producer run in the model.
- **R232-9 — hosted exact-head proof.** A manual proof-only workflow path runs
  the production decision/reconciliation code against synthetic state and
  uploads a red/green evidence artifact. Proof mode cannot select or mutate the
  production receipt source. After merge, the proof is run on the exact merged
  head and its run/artifact identities are recorded.

## Rejection behavior

- Never place the watchdog inside the producer workflow or gate execution on a
  producer run, job, artifact, or conclusion.
- Never accept a body-only day claim whose GitHub timestamp lies outside the
  day, a timestamp-only unrelated comment, a malformed response, or an
  incomplete pagination result as presence.
- Never turn read/reconciliation failure into green, silently suppress an
  absent verdict, create one incident per day, duplicate a day's history on
  retry, or auto-close an alarm.
- Never change producer scheduling, launching, preflight, receipt publication,
  image pinning, or the cna#202 single tagged-digest contract.

## Invariants

All rows are required for ticket acceptance. Their mutation-campaign severity
is `ADVISORY`: none constrains chain state, money, or a signature.

| ID | Severity | Observable truth | Demonstrated failure | Observable success |
|---|---|---|---|---|
| INV-232-1 | ADVISORY | Watchdog reachability is independent of the producer | the synthetic model contains no producer run and no receipt | the independently invoked watchdog returns `ABSENT`, reconciles an alarm, and exits non-zero |
| INV-232-2 | ADVISORY | The scheduled target is the previous closed UTC day | clock values across month/year boundaries and near midnight are injected; supplied producer data is absent | output names the mathematically previous UTC date and its exact closed interval |
| INV-232-3 | ADVISORY | Presence is an authentic dated receipt, not an accidental match | wrong marker, wrong day, before/after timestamps, malformed JSON, and later pages are varied independently | only an exact marker/day comment inside the interval contributes to the positive count |
| INV-232-4 | ADVISORY | Missing receipt makes the real signal red | the synthetic receipt set is empty | reconciliation creates the canonical incident, evidence says `ABSENT count=0`, and the command exits non-zero |
| INV-232-5 | ADVISORY | Repeats converge without erasing history | the same absent day is retried and a second absent day follows | exactly one open marked incident exists and contains exactly one durable row for each day |
| INV-232-6 | ADVISORY | Recovery is visible and never silently closes red | a valid receipt is restored while the incident remains open | verdict is `PRESENT`, evidence names a positive count, no new incident exists, and the prior incident remains open |
| INV-232-7 | ADVISORY | Observation and reconciliation failures fail closed | read, pagination, parse, create, and update boundaries are individually failed | each exits non-zero with a distinct error and no false green or misleading history claim |
| INV-232-8 | ADVISORY | Production wiring and proof wiring cannot become vacuous | mutations remove the schedule caller, substitute the producer workflow, skip the script, or bypass a control leg | CI executes both red and green controls while the scheduled job directly calls the watchdog |
| INV-232-9 | ADVISORY | Evidence is public-safe and revision-bound | secret-shaped fixture values and unstable URLs are supplied | evidence omits them and names exact SHA, day, stable GitHub IDs, and verdict |

## Observable success

- `just test-daily-amaru-watchdog` prints counted `WATCHDOG-NEGATIVE`,
  `WATCHDOG-REPEAT`, `WATCHDOG-POSITIVE`, and `WATCHDOG-NO-RUN` evidence and
  exits 0 while proving the inner absent command exited non-zero.
- The immutable slice gate is observed RED on the frozen base and GREEN on the
  candidate; complete `just ci` remains green without network or credentials.
- A post-merge `workflow_dispatch` proof run on the exact merged head uploads
  the same red/green evidence before the alarm is claimed live.

## Scope

Owned production surface is one new watchdog workflow and one new watchdog
script. Focused tests, fake GitHub boundary fixtures, `justfile`, workflow
validation, and `specs/232-*` may change only for this contract. The existing
Daily Amaru producer files and semantics, property accounting, Antithesis API,
run correlation, digests, launcher, preflight, and image repin are forbidden.
