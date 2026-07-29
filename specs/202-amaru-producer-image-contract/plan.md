# Plan — Issue 202

## Technical context

The unchanged tree contains three active references to
`ghcr.io/lambdasistemi/amaru-bootstrap-producer`, all in
`testnets/cardano_amaru/docker-compose.yaml` and all currently identical and
digest-pinned. That count and value are observations, not implementation
constants.

The repository convention already provides:

- `scripts/` for mechanical shell checks,
- a tracked root `gate.sh` for local acceptance, and
- `.github/workflows/publish-images.yaml`, which runs for pull requests to
  `main` and already owns the image/Compose CI boundary.

The tracked `gate.sh` is a permanent project gate inherited from issue #193,
not a resolve-ticket lifecycle sentinel. It remains tracked and is extended in
place.

## Slice 1 — Add and wire the contract check

This is one bisect-safe implementation commit executed by the standing Qwen
driver and an independent navigator.

Owned implementation files:

- `scripts/check-amaru-producer-image-refs.sh`
- `gate.sh`
- `.github/workflows/publish-images.yaml`

The checker accepts an optional Compose-root argument for controlled evidence;
the production default is `testnets/`. It recursively discovers Compose files,
extracts matching image fields, rejects an empty census, validates every value
as a tagged 64-hex SHA-256 digest reference, and rejects more than one unique
value. Its success line prints the observed count and unique reference.

The driver proves RED before GREEN with temporary copied Compose input outside
the tracked tree:

1. Change exactly one discovered reference to another syntactically valid
   tag-plus-digest and require non-zero exit.
2. Remove the digest from exactly one discovered reference and require
   non-zero exit.
3. Preserve raw stdout/stderr and exit codes under the lane evidence root;
   delete neither evidence nor the temporary input until the ticket owner has
   independently checked it, but never stage either.
4. Run the checker on the unchanged repository tree and require success.
5. Run `./gate.sh` and require success.

The tracked gate invokes the checker directly. The existing PR-triggered
publish-images workflow also invokes the checker directly before publishing,
so CI reachability is visible in workflow source and in the PR check log.

Commit subject:

`ci: enforce Amaru producer image references`

Commit trailer:

`Tasks: T202`

## Ticket-owner acceptance

The ticket owner independently:

1. Reviews the complete commit and verifies only the three owned files changed.
2. Replays both seeded RED controls into fresh temporary directories.
3. Runs the clean checker and full tracked gate.
4. Confirms neither seed is present in the commit or worktree.
5. Pushes the accepted slice and verifies the PR-triggered workflow log contains
   the check's non-vacuous pass output.
6. Updates the human-readable PR body with the evidence and requests merge
   authorization from the Milestone 1 desk through
   `/tmp/ms-1/cna-image-check/questions/`.

## Post-merge Milestone 1 closeout

After authorized merge, refresh final `main` and launch the closing 60-minute
fault-injection Antithesis run using the report template at
`/tmp/ms-1/cna-fix-run/run-report.md` and the MOOG procedure established by
issue #200.

The closing report must account for every property. Both #1098 fatal consensus
signatures must be absent. The only expected reds are
`pragma-org/amaru#1104` and `cardano-node-antithesis#140`; every other red is a
genuine finding requiring evidence and ownership/filing.

