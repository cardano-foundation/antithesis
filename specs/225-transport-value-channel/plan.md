# Plan

## Strategy

Two defects, one bisect-safe slice, because the regression harness that proves
either one is the same harness: the real transport executed against a local
git boundary.

### Why the class was invisible until production

Every existing Daily Amaru proof drives the **controller** against
`tests/fixtures/daily-amaru/fake-transport.sh`, or inspects the **text** of
`scripts/daily-amaru-github.sh` with mutants. Nothing executes the real
transport's git path. The value channel is a property of the real subcommands —
`git commit` writes its summary to stdout — so no controller-level or
text-level check could observe it. This is the [[live-boundary-smoke]] shape:
unit-green, production-broken, at the seam.

The fix therefore ships a boundary the tests can actually reach: a bare local
repository standing in for the bootstrap remote, real `git`, a `gh` stand-in
that implements the clone/PR surface, and a deterministic lock rewriter
standing in for `nix flake lock`. Real `git` is mandatory — its stdout
behaviour **is** the defect.

## Live boundary and its limits

The stand-ins must not be politer than the real binaries. Concretely:

- `git` is the real binary; nothing may stub it.
- The `gh` stand-in's `repo clone` delegates to real `git clone`.
- The lock rewriter rewrites `flake.lock` exactly as `nix flake lock
  --override-input` does for the pinned node (rev + narHash + lastModified),
  and writes its progress where the real `nix` writes it.

Residual risk this design does **not** close: divergence between the `gh` and
`nix` stand-ins and their real binaries. That risk is bounded by keeping both
stand-ins to the exact subcommand surface the transport invokes, and by the
structural (not per-command) value-channel mechanism, which holds regardless of
what any stand-in prints.

## Ordered work

One slice `S1`. Within it:

1. RED first: the boundary harness plus the failing proofs for both classes,
   against unmodified `scripts/daily-amaru-github.sh`. The pollution proof must
   fail with exactly `malformed-candidate-sha`; the adoption proof must fail at
   the non-fast-forward push.
2. Value channel: the structural mechanism, applied across every value-returning
   operation.
3. Proposal adoption: `absent | adoptable | foreign` classification before any
   mutation of the workspace or the remote.
4. Mutants for every protection, each proved to apply and to be rejected.

Splitting 2 from 3 would leave `main` with a re-attempt that pushes
non-fast-forward, i.e. a bisect point that is worse than either endpoint.

## Constraints on the implementation

- No change to `scripts/daily-amaru.sh` unless the fix genuinely needs it. The
  controller's validation regexes and `receipt_keys` are frozen.
- No workflow YAML change. `.github/workflows/daily-amaru.yaml` already runs
  `tests/test-daily-amaru.sh`; new proofs must land inside that suite (or a
  suite `just ci` already runs) so they execute in the six required contexts.
- New tests build their own repositories under `mktemp -d`. They must not read
  this repository's history, so they survive a shallow checkout.
- `just check-shell` shellchecks `scripts/*.sh` and `tests/*.sh` including
  fixtures; new fixtures must pass `shellcheck -x` and `just format-check`.
- No network. No credentials. No real Antithesis launch. The existing effect
  censuses (`assert_no_launch`, `assert_no_mutation`, `EFFECT-CENSUS`) must stay
  honest — a new proof may not make them count effects from a different lane.

## Verification

`./gate.sh` (ticket runtime, untracked) runs `nix develop --quiet -c just ci`
plus the focused ticket proofs. Baseline on `01f96e4`: exit 0, 20.8s.
