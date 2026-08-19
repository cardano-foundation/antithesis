# Modules model — Issue 221

Artifact ceiling: 2,500 bytes and 60 lines.

Only changed responsibilities are listed. Dependency direction is unchanged:
the controller depends on the transport contract; the transport never depends
on the controller.

## M221-01 — `scripts/daily-amaru.sh` (Daily Amaru controller)

Changed responsibility: the controller is the sole deriver **and the sole
publisher** of the validated UTC day to its transport children. Owning the
value without publishing it was the defect; publication is part of the
derivation responsibility, not of the transport's.

The publication channel is the process environment, matching the existing
`DAILY_AMARU_STATE_DIR`, `DAILY_AMARU_RECEIPT`, and `DAILY_AMARU_IDENTITY`
promotions already performed by this component. No new component, no new
channel, and no promotion to a shared upstream owner: exactly one consumer
family exists and it is the transport this controller already owns.

Unchanged: derivation source, validation, stage sequencing, receipt
composition and ordering, identity handling, and launch selection.

## M221-02 — `scripts/daily-amaru-github.sh` (production transport)

Unchanged and read-only in this ticket. It remains the authority on which
operations require the day. Its source is the declared side of the
reconciliation in M221-03.

## M221-03 — `tests/fixtures/daily-amaru/fake-transport.sh` (fixture transport)

Changed responsibility: the deterministic transport gains the ability to
observe the day seam. It binds the day with the same expansion the production
transport uses, in exactly the operation set derived from M221-02, and records
the observed value in the effect log it already owns.

This fixture holds no contract authority of its own. Its agreement with M221-02
is asserted mechanically by M221-04; without that assertion the fixture would
be a check that can stop being able to fail.

## M221-04 — `tests/test-daily-amaru.sh` (focused controller proof)

Changed responsibility: the focused proof additionally owns the workflow-shaped
omitted-day class — derived-day propagation, the killing mutant, receipt
survival through a downstream failure, and the declared-versus-observed
reconciliation between M221-02 and M221-03.
