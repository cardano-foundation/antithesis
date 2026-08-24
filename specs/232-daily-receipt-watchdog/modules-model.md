# Modules model — Issue 232

Artifact ceiling: 3,000 bytes and 75 lines.

Only new or changed responsibilities are listed. Dependency direction is
watchdog workflow → watchdog executable → GitHub receipt/incident boundary.
No dependency points from the producer into the watchdog.

## M232-1 — independent watchdog workflow

Owns the independent schedule, minimal permissions, production invocation,
proof-only manual invocation, always-uploaded verdict artifact, and
non-cancelling watchdog concurrency. It does not invoke or inspect the producer
workflow and does not own receipt publication.

## M232-2 — `scripts/daily-amaru-watchdog.sh`

Owns previous-UTC-day derivation, paginated canonical receipt observation,
`PRESENT`/`ABSENT`/`ERROR` evidence, and canonical incident reconciliation.
It consumes GitHub comment identities and timestamps only; it does not own
property accounting, run correlation, producer status, or receipt contents
beyond the marker and day identity.

## M232-3 — GitHub observation/reconciliation boundary

Owns authenticated reads of all cna#210 comment pages and the minimal issue
list/create/comment operations for the marked alarm. It returns raw boundary
results or errors, never a watchdog verdict. Production uses GitHub CLI; tests
inject a hermetic fake with the same externally observed contract.

## M232-4 — focused watchdog proof

Owns deterministic clock and GitHub boundary state, both-direction verdict
controls, incident/history/recovery assertions, workflow reachability mutants,
public-evidence checks, and zero-network/zero-credential accounting. It is
wired into the repository's canonical CI entry.
