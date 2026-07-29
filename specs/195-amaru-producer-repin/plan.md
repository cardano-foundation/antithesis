# Plan — Issue 195

## Technical context

The consumed artifact appears exactly three times in
`testnets/cardano_amaru/docker-compose.yaml`: the shared Amaru relay anchor,
`bootstrap-producer`, and `amaru-consumer-seed`. The reference count matches
the issue contract. No production file other than that Compose file is in the
implementation fence.

The repository's existing `gate.sh` validates the `cardano_amaru` Compose
model and runs the fatal-log/property test suite. It is reused unchanged:
changing findings-gate or constitution semantics requires escalation and is
not part of this ticket.

## Slice 1 — Repin all Compose consumers

This is one mechanical, bisect-safe configuration commit.

1. Prove the proposed exact-reference census is RED on the old pin while the
   old-reference positive control finds exactly three entries.
2. Replace all three old producer-image references with the binding
   tag-plus-digest.
3. Prove the new-reference count is exactly three and the old-reference count
   is zero.
4. Run Compose validation, `./gate.sh`, and
   `./scripts/smoke-test.sh cardano_amaru 600`.
5. Commit the reviewed YAML as
   `chore(cardano_amaru): repin producer image` with `Tasks: T195`.

## Post-merge operation

After the milestone desk authorizes the merge on the file-protocol record:

1. Merge the PR and identify the resulting `main` commit.
2. Use the release MOOG binary and requester identity to launch a one-hour
   `testnets/cardano_amaru` run at that merged commit.
3. Wait for terminal Antithesis state, then pull the full property set through
   the Antithesis REST API.
4. Identify the fatal-consensus property as the expected red owned by
   `pragma-org/amaru#1098`; triage every other red as a genuine finding.
5. Report the run id, report URL, tested image, and pass/fail result for every
   property to the milestone desk.
