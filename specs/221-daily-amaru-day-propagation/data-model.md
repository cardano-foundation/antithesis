# Data model — Issue 221

Artifact ceiling: 2,500 bytes and 60 lines.

## D221-01 — `DAILY_AMARU_DAY` (process-environment field)

- **Owner:** M221-01 (controller).
- **Consumers:** every transport child forked by the controller; today
  `propose-bootstrap` and `prepare-consumer-repin` bind it as required.
- **Type:** string matching `^[0-9]{4}-[0-9]{2}-[0-9]{2}$`.
- **Source:** the caller-supplied value when present, otherwise the
  controller's own UTC derivation.
- **Validation:** the existing day regex, applied before publication. An
  invalid day still aborts the run before anything is published.
- **Channel:** process environment only. Never a command-line argument, never a
  file, never a persisted artifact.

### State invariants

- **D221-01-I1.** Publication happens after validation and before the first
  transport child is forked; no transport child may observe an unvalidated or
  absent day.
- **D221-01-I2.** The published value equals the value the controller recorded
  in `receipt[day]`, so the durable receipt and every transport child agree on
  one day for the whole run.
- **D221-01-I3.** Publication is idempotent with respect to a caller-supplied
  day: when the environment already carried a valid day, the published value is
  that same day.

## D221-02 — Effect-log day observation (fixture-owned record)

- **Owner:** M221-03.
- **Content:** the day value observed inside the transport child, recorded
  alongside the existing per-operation effect record.
- **Constraint:** it records the observed environment value only. It must not
  synthesize, default, or repair a missing day, or the mutant becomes
  unkillable.
