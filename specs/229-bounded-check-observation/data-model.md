# Data model — Issue 229

Artifact ceiling: 3,000 bytes and 75 lines.

## D229-1 — required-check observation

- candidate: exact 40-hex bootstrap head;
- check name: member of the unchanged required-check set;
- lifecycle: not reported, queued/in-progress, or completed;
- conclusion: success or non-success only when completed;
- multiplicity: number of candidate-exact rows;
- transport result: valid response or retryable observation error.

State invariant: `successful` requires exactly one candidate-exact completed
success row for every required name. A transport error is never a lifecycle or
conclusion value.

## D229-2 — observation window

- provenance: observed historical behavior or declared duration evidence for
  the observed check/workflow surface;
- start/deadline: finite values derived from that evidence and the current
  observation clock;
- cadence/effect count: observable polls and sleeps within the deadline.

The window must respond to changed injected duration evidence. Missing,
malformed, non-positive, or unbounded evidence fails closed rather than
silently selecting an unrelated constant.

## D229-3 — terminal outcome

Exactly one of:

- `successful`: D229-1 is uniquely successful for every required check;
- `failed`: a named required check has a concluded non-success or an ambiguous
  terminal census;
- `never-reported`: a named required check remains absent at D229-2's deadline;
- `transport-exhausted`: observation transport never recovers by the deadline.

Every non-success is non-zero and names the outcome; `failed` and
`never-reported` may not share the old conflated diagnostic.
