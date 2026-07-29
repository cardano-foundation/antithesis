# Plan — Issue 200

## Technical context

The consumed artifact appears exactly three times in
`testnets/cardano_amaru/docker-compose.yaml`: the shared Amaru relay anchor,
`bootstrap-producer`, and `amaru-consumer-seed`. A Compose-tree fixed-string
census on unchanged `origin/main` found exactly those three references, so
the issue's expected count is not presently drifting.

The current reference is the image validated by issue #195:

`ghcr.io/lambdasistemi/amaru-bootstrap-producer:2d0f4451630b7587851e9238cb43a34e3200e8cf@sha256:deff22e851d9703b344a75c20f5deeb8374258f3cc5716edf237e69d2f5ab108`

The replacement is the immutable image published after
`lambdasistemi/amaru-bootstrap#74` merged:

`ghcr.io/lambdasistemi/amaru-bootstrap-producer:cf657b918787c213c09ffef3879ac4a2552dd680@sha256:72906da307862ee5652a35d2e6569fcd929ddd5785ad6d633b42e4912faef147`

Only `testnets/cardano_amaru/docker-compose.yaml` is inside the
implementation fence. The repository's tracked `gate.sh` is a permanent
fatal-log/property and Compose gate from issue #193, not a resolve-ticket
lifecycle sentinel; it is reused unchanged and must not be dropped.

## Slice 1 — Repin all Compose consumers

This is one mechanical, bisect-safe configuration commit executed by a Qwen
driver and an independent navigator.

1. Freeze RED evidence showing the new exact-reference count is zero while
   the old-reference positive control finds exactly three Compose entries.
2. Replace all three old producer-image references with the binding
   tag-plus-digest.
3. Freeze GREEN evidence showing the total producer-reference count is
   three, the exact required-reference count is three, and the count on any
   other tag or digest is zero.
4. Run Compose validation, `./gate.sh`, and
   `./scripts/smoke-test.sh cardano_amaru 600`.
5. Commit the reviewed YAML as
   `chore(cardano_amaru): repin producer image` with `Tasks: T200`.

The ticket owner independently re-runs the census, gate, and smoke before
accepting and pushing the commit.

## PR and merge gate

The draft PR records the old and new immutable references plus the exact
three/three/zero census. The ticket owner asks the milestone desk for merge
authorization through `/tmp/ms-1/cna-fix-run/questions/` and does not merge
until the matching answer file explicitly authorizes it.

## Post-merge decisive run

After the authorized merge:

1. Resolve the resulting `main` merge commit and use the release MOOG
   procedure from issue #195 to submit a 60-minute fault-injection run for
   `testnets/cardano_amaru`.
2. Wait for terminal Antithesis state and retain run metadata, the complete
   property payload, signature searches, and first failure moments.
3. Prove the fatal-log search instrument can produce known hits against
   retained #195 evidence before treating a zero-result search as absence.
4. Require `no fatal amaru consensus logs` to score with zero
   counterexamples and require both #1098 signatures to be absent.
5. Treat the #1104 rewards panic/container exits as declared expected red and
   the #140 stale-consumer fork-depth result as an expected artifact.
6. Triage every other red as a genuine finding and file it upstream with
   evidence when unowned.
7. Deliver the full per-property report and explicit ABSENT/RED accounting to
   the milestone desk.

If either fatal signature appears, stop normal triage immediately, retain the
raw evidence, and escalate to the desk: that outcome invalidates the
supplier fix under fault injection.
