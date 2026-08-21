# Modules model — Issue 227

Artifact ceiling: 3,000 bytes and 70 lines.

Only changed responsibilities are listed. The dependency direction is
controller → transport orchestrator → cloned bootstrap resolver; the resolver
never depends on this repository.

## M227-1 — `scripts/daily-amaru-github.sh`

Changed responsibility: `propose-bootstrap` owns the atomic transaction around
an Amaru pin change. It invokes M227-2, pairs the lock with its generated
record, validates the exact two-path/one-commit candidate, and permits push/PR
effects only after the complete transaction succeeds. Existing-branch
classification enforces the same candidate shape.

It does not own or reproduce the peer-snapshot selection rule.

## M227-2 — cloned `scripts/resolve-peer-snapshots` (read-only dependency)

Unchanged responsibility: sole online bump-time authority for the selected
configurations revision and recorded snapshot hashes. It is consumed from the
exact cloned repository and never copied, patched, or invoked by build/verify
paths.

## M227-3 — Daily Amaru receipt boundary

Changed only as required to preserve the resolver-specific failure identity as
`peer-snapshot-resolution-failed` within the existing receipt field set.
Stage ordering, receipt keys, and every other failure class stay unchanged.

## M227-4 — focused Daily Amaru boundary proof

Changed responsibility: the local git boundary models M227-2's command
contract, observes invocation and effects, proves atomic creation/adoption and
named failure, and kills lock-only/skip-resolver mutants. It inherits no host
commands and performs no real publication or launch.
