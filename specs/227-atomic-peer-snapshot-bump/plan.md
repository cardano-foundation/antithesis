# Plan — Issue 227 atomic peer-snapshot bump

Artifact ceiling: 6,000 bytes and 140 lines.

## Technical context

The issue lane starts from frozen main `83577835`. The direct baseline
`just test-daily-amaru` exits 0 in 62.4 seconds; receipt and full output are at
`/tmp/ms-cardano-node-antithesis-2/e-auto/t227-codex-to-01/evidence/baseline-daily.log`.

The standard local dev shell is cold. Its dry run reports two derivations plus
one 1.58 MiB download (5.37 MiB unpacked). Durable answer A-001 authorizes no
realization: local acceptance uses injected shell boundaries, while all exact-
head hosted contexts supply the omitted actionlint/shellcheck coverage. This
omission is named in every final gate receipt and in the PR body.

## Architecture decisions

- `scripts/daily-amaru-github.sh` remains the proposal orchestrator. It updates
  inputs, invokes the cloned repository's rule authority, validates the atomic
  result, and publishes only after all of those operations succeed.
- `scripts/resolve-peer-snapshots` in the clone remains the sole resolution
  authority. Its documented interim mismatch and final verification are
  treated as one fail-closed bump transaction; no rule is copied into this
  repository.
- The existing local git boundary is extended with an injected clone-local
  resolver and a non-default configurations revision. Real git remains in the
  boundary because commit count and changed-path atomicity are observable only
  there. Network, credentials, GitHub publication, and Nix realization remain
  replaced by deterministic stand-ins.
- Proposal adoption is the same contract as proposal creation: exactly one
  commit, exactly the two paths, and coherent lock/record revisions. The PR #86
  shape is a permanent foreign-branch mutant.
- A resolver-specific transport failure crosses to the existing receipt model
  without changing its keys. Only the error value is specialized.

## Slice

One bisect-safe OWNER slice, **S227-01**. Atomic commit history, cross-file
consistency, external-tool ownership, and typed failure transport require
semantic audit; the slice is not eligible for LIGHT.

The commit owner supplies the complete RED proof before production changes,
then lands the production and permanent regression together. Splitting the
proof, resolver invocation, paired pin, census, or receipt path would create a
commit that can publish the split state this issue exists to prevent.

## Proof strategy

- Exercise fresh and adoptable proposals through local bare repositories and
  the real transport with injected `gh`, `nix`, and clone-local resolver
  boundaries.
- Use distinguishable old, Amaru, selected-configurations, and foreign values;
  no default or equal fixture value may satisfy consistency accidentally.
- Demonstrate the exact lock-only PR #86 mutant and a skip-resolver mutant are
  applied and rejected for the intended atomicity reason.
- Force resolver non-zero and malformed-result cases after the Amaru override;
  require the named failure receipt and prove remote refs plus PR/push effects
  are unchanged.
- Derive every marker count from executed observations and retain the existing
  zero-real-launch/effect fences.

## Verification envelope

- Frozen untracked `./gate.sh` and its runtime backup.
- Focused atomic-boundary scenario and complete `just test-daily-amaru`.
- Shell syntax and exact changed-path/invariant marker checks.
- No local `nix develop -c just ci`; A-001 names this host-forbidden omission.
- All required hosted contexts green on the exact final head.

## Stop conditions

Stop and ask before editing the bootstrap resolver/anchor, changing receipt
keys or cap/supersede semantics, using network or credentials in tests,
launching Antithesis, realizing Nix locally, or widening production scope.
