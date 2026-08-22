# Modules model — Issue 229

Artifact ceiling: 2,500 bytes and 60 lines.

Only changed responsibilities are listed. Dependency direction remains Daily
controller → GitHub transport → observed bootstrap Actions state.

## M229-1 — `scripts/daily-amaru-github.sh`

Changed responsibility: `require-bootstrap-checks` owns bounded observation of
the existing required checks on the exact bootstrap candidate. It distinguishes
pending, successful, failed, never-reported, and transport-exhausted outcomes;
it proceeds only on exact unique success.

It does not own required-check membership, proposal construction, receipt
schema, cap/supersede state, or bootstrap workflow definitions.

## M229-2 — bootstrap Actions observation boundary

Changed responsibility: expose candidate-exact check lifecycle state and the
observed or declared duration evidence needed to derive a finite observation
window. Transport failure is a boundary failure, not a check lifecycle value.

## M229-3 — focused Daily Amaru boundary proof

Changed responsibility: inject sequenced lifecycle observations, duration
evidence, clock/sleep effects, and transport faults; prove every terminal and
recovery state, kill the immediate-read mutant, and account for zero external
effects. The boundary seeds every command and inherits none from the host.
