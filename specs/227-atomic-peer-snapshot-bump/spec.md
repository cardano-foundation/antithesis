# Atomically refresh peer snapshots in unattended Amaru bumps

Issue: cardano-foundation/cardano-node-antithesis#227 · parent epic #205
Frozen main base: `83577835d67bb97af2a19b1680f4aafbc9cc9528`

Artifact ceiling: 8,000 bytes and 180 lines.

## Context

Daily fire run 32447033481 created amaru-bootstrap PR #86 at candidate
`ecda90be`. It changed only `flake.lock`: the Amaru pin moved while
`nix/peer-snapshots/resolution.json` and the configurations pin stayed old.
The unchanged `peer-snapshot-anchor` rejected that split state, and its
negative control proves the alarm is load-bearing.

## Requirements

- **R227-1 — resolver ownership.** After overriding the cloned bootstrap
  repository's Amaru input, `propose-bootstrap` invokes that clone's shipped
  `scripts/resolve-peer-snapshots --write`. The controller consumes it
  unmodified and does not duplicate its date, revision, or hash rule.
- **R227-2 — exact paired pin.** The bootstrap candidate locks
  `cardano-configurations` to exactly the revision selected and recorded by
  the resolver for the new Amaru revision.
- **R227-3 — atomic proposal.** One proposal commit contains exactly
  `flake.lock` and `nix/peer-snapshots/resolution.json`. Its lock and record
  agree on both revisions; no intermediate or final lock-only proposal is
  pushed.
- **R227-4 — exact census.** Fresh and adoptable proposal classification
  accepts exactly those two paths and rejects any missing or additional path.
  The PR #86 shape is therefore foreign, never adoptable.
- **R227-5 — fail closed.** Network, rate-limit, malformed result, rule
  mismatch, or final resolver verification failure produces the stable
  receipt error `peer-snapshot-resolution-failed`, returns non-zero, and
  performs no proposal push or PR creation.
- **R227-6 — anchored verification stays anchored.** The bootstrap resolver,
  `peer-snapshot-anchor`, its negative control, and bootstrap checks are
  unchanged. The proposal passes them by supplying the coherent bundle.

## Rejection behaviour

- Never edit or bypass amaru-bootstrap's resolver or anchor checks.
- Never accept a lock-only branch, a record-only branch, multiple proposal
  commits, a third changed path, or a record whose revisions disagree with the
  lock.
- Never turn a resolver error into an ordinary candidate SHA or a generic
  success-path receipt.

## Invariants

All rows are `BLOCKING`: these unattended pins configure a node that consumes
chain state, so no survivor may be accepted as a residual.

| ID | Severity | Observable truth | Demonstrated failure | Observable success |
|---|---|---|---|---|
| INV-227-1 | BLOCKING | The cloned repository's shipped resolver is the rule authority | a skip-resolver mutant reproduces PR #86 and is rejected | the injected boundary records one clone-local resolver invocation after the Amaru override |
| INV-227-2 | BLOCKING | The lock and resolution record carry the new Amaru rev and exactly the resolver-selected configurations rev | either recorded revision or either lock revision is mutated | both pairs agree and the injected resolver's non-default selected revision is preserved |
| INV-227-3 | BLOCKING | The proposal is one commit with exactly the two contractual paths | split commits, lock-only, record-only, or an extra path | commit count is one and path census equals the two-path set |
| INV-227-4 | BLOCKING | Existing-branch adoption applies the same atomic census and consistency checks | the exact PR #86 lock-only branch is offered for adoption | coherent two-path branch is adopted without mutation; incoherent branch is named foreign |
| INV-227-5 | BLOCKING | Resolver failure is a named red before publication | injected resolver fails after the Amaru override | receipt says `stage=bootstrap-proposal`, `outcome=FAILED`, `error=peer-snapshot-resolution-failed`; push and PR counts stay zero |
| INV-227-6 | BLOCKING | The proof cannot spend or weaken the anchor | a test reaches a real workflow launch or changes an anchor surface | injected transports only, zero real launches, and no bootstrap-repository edit |

## Observable success

- The workflow-shaped injected boundary proves INV-227-1 through INV-227-6,
  including a verified-applied skip-resolver mutant and resolver-error control.
- `just test-daily-amaru` is green without network, credentials, push, PR
  publication, or Antithesis launch.
- The local cold Nix CI leg is explicitly omitted under durable A-001 because
  it would realize two derivations; all required hosted contexts must be green
  on the exact pushed head and cover actionlint/shellcheck there.

## Scope

Owned production surface is `scripts/daily-amaru-github.sh`, with a minimal
`scripts/daily-amaru.sh` change only if needed to preserve the named failure in
the receipt. Focused tests and fixtures plus `specs/227-*` are owned.
Receipt schema, cap/supersede semantics, credentials, workflows, real launches,
and every amaru-bootstrap file are forbidden.
