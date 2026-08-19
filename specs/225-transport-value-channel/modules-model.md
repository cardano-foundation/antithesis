# Modules model

Only changed responsibilities. References `data-model.md` and
`functions-model.md` without repeating them.

## M-225-1 `scripts/daily-amaru-github.sh` — transport

Existing responsibility: execute one named side-effecting operation and return
its value to the controller.

Changed: the transport now **owns the separation of its two output streams**.
The value channel is a dedicated descriptor reserved at dispatch; fd 1 becomes
the diagnostic stream for the whole script, so every subcommand's stdout is
diagnostic by construction. Operations reach the value channel only through the
emit function in `functions-model.md`.

Dependency direction unchanged: transport → external binaries. The controller
(`M-225-2`) keeps consuming stdout and is not aware of the mechanism.

Promotion: none. The mechanism is transport-local; no shared library exists in
this repository and creating one for a single consumer is not justified.

## M-225-1a `propose-bootstrap` — proposal adoption

New responsibility: **classify the per-SHA proposal branch on the bootstrap
remote before mutating anything**, then act on that classification. The three
states and the named red are in `data-model.md`.

The classification is a read of the bootstrap remote and must complete before
the local branch is created, before `nix flake lock` runs, and before any push.
Ordering is the invariant: a classification performed after a local commit
cannot prevent the non-fast-forward push it exists to prevent.

`prepare-consumer-repin` is explicitly **not** given this responsibility in this
slice. Its branch is per-day, not per-SHA, and its re-attempt semantics are a
separate contract; only its value-channel defect is in scope.

## M-225-2 `scripts/daily-amaru.sh` — controller

Unchanged responsibility and unchanged validation. It is edited only if the
value-channel mechanism genuinely requires it; `receipt_keys`, the stage names,
and every validation regex are frozen.

## M-225-3 `tests/fixtures/daily-amaru/` — boundary stand-ins

New responsibility: provide a **local bootstrap remote boundary** so the real
transport's git path is executable without network, credentials, or the live
`lambdasistemi/amaru-bootstrap`.

Consists of a bare repository standing in for the remote, the existing `gh`
stand-in extended to the exact subcommand surface the transport invokes, and a
deterministic lock rewriter standing in for `nix flake lock`. Real `git` is a
dependency of this module and may not be stubbed.

Dependency direction: tests → fixtures → real `git`. Fixtures never import from
`scripts/`; the transport is executed as a black box, exactly as CI runs it.

## M-225-4 `tests/test-daily-amaru.sh` — proof suite

Existing responsibility: the focused Daily Amaru proof, run by `just ci` and by
the `daily-amaru` workflow's pull-request job.

Changed: gains the value-channel census over every value-returning operation and
the three proposal-branch scenarios, each with a mutant. Its existing effect
censuses keep their current meaning; new proofs account for their effects
separately.
