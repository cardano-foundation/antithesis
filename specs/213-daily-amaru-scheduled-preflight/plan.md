# Plan — Issue 213 Daily Amaru scheduled preflight

Artifact ceiling: 8,000 bytes and 180 lines.

## Technical context

The frozen and freshly revalidated base is
`311dfc1d499277b23035a107eaf0ec097cf3d948`. The existing local ticket gate is
green on that tree, while scheduled runs 30734090142 and 30787205335 failed
before controller state with the exact missing-`rg` fingerprint. The same
scheduled environment exposed no production identity.

Parent answer A-001 selects a dedicated least-privilege GitHub App installed
only on `lambdasistemi/amaru-bootstrap`. Local implementation is released;
App creation/installation, secret placement, workflow dispatch, real launch,
merge, and downstream ticket release remain forbidden.

## Architecture

The module responsibility changes are defined in `modules-model.md`; receipt
and identity fields are defined in `data-model.md`; changed interfaces are
defined in `functions-model.md`.

The scheduled workflow owns explicit tool availability, dedicated App-token
minting, short-lived token binding, and durable publication of the local
receipt. The controller owns precondition ordering and receipt-first failure
semantics. The GitHub transport owns command validation and enforces the
bootstrap-versus-consumer identity boundary. Focused proof owns incident
reproduction, negative controls, side-effect counts, and production wiring
reachability.

No new general orchestration framework is introduced. A focused receipt or
preflight helper is permitted only if it has one responsibility already named
by the module model and is required to keep the failure sink independent of
the failed transport dependency.

## Proof strategy

The immutable slice gate binds INV-213-01 through INV-213-09 and the complete
owned-path fence. Before implementation it must:

- reproduce both exact dated missing-`rg` fingerprints on `311dfc1`;
- demonstrate that the current path has no durable receipt for that failure;
- reject missing, partial, non-failure, and vague receipt records;
- positively accept a complete synthetic failure receipt so absence checks do
  not rely on a broken instrument;
- remain red until scheduled App wiring, identity separation, negative
  controls, and explicit evidence signals exist.

GREEN requires the focused suite, immutable slice gate, historical Daily
Amaru ticket gate, shell analysis, producer-reference census, live entrypoint
contract, and `git diff --check`. Gate output names evidence counts rather than
passing silently.

## Slice S213-01 — Scheduled preflight and identity boundary

Topology is `OWNER`. The slice crosses workflow security, state-machine
failure ordering, credential scope, and durable receipt semantics, so a
mechanical LIGHT gate is insufficient.

- Ticket owner: Codex, pane `%5294`.
- Commit owner: fresh Claude Code using `claude-opus-5[1m]`, effort `high`.
- Draft tool: `NONE`; qwen and agy are not authorized for this slice.
- Commit auditor: fresh Codex using `gpt-5.6-sol`, effort `xhigh`, in a clean
  detached worktree after each submission.
- Audited submissions: maximum two; one findings-driven owner repair only.
- Commit owner and auditor have no push, remote-publication, live-dispatch,
  secret-setup, or merge authority.

The owner creates one complete RED commit and one GREEN candidate, then parks
write-idle. The auditor independently inspects the consolidated diff and
reproduces every invariant. After acceptance, only the task stamp may differ
from the audited tree before the owner creates the final squashed commit.

Predetermined final commit:

`fix(ci): harden Daily Amaru scheduled preflight`

The body explains explicit scheduled dependencies, dedicated bootstrap App
scope, and loud durable precondition receipts. The trailer is:

`Tasks: T2131, T2132, T2133, T2134, T2135, T2136`

## Verification and resource fence

The complete ticket gate runs focused checks before the prior repository gate.
Every expensive command records available bytes before and after. Scratch and
audit worktrees live under `/code`; `/run` is not used for scratch. Stop if
`/` falls below 30 GiB, a command consumes more than 8 GiB, or consumption
continues unexplained after exit.

No production workflow dispatch or real launcher is part of verification.
Hosted checks are observed only on the exact pushed candidate head. The live
App setup gate remains explicit in the final handoff.
