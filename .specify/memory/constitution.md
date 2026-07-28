# cardano-node-antithesis Constitution

Principles that govern every spec / plan / task on this repo. Derived from the repo's existing conventions and the `antithesis-tests` skill.

## Core Principles

### I. Composer-first workload
Every workload we put into `testnets/cardano_node_master/docker-compose.yaml` must be expressed through the Antithesis Test Composer (commands under `components/<name>/composer/<template>/`). No side-channel harness, no inline entrypoint scripts driving behavior. The seven prefixes (`first_`, `parallel_driver_`, `serial_driver_`, `singleton_driver_`, `anytime_`, `eventually_`, `finally_`) are the only sanctioned scheduling primitives.

### II. SDK instrumentation is mandatory
Every non-trivial composer command emits at least one Antithesis SDK assertion per meaningful control-flow moment: `reachable` on entry, `sometimes` around every success/failure branch, `always` on true invariants, `unreachable` on impossible branches. A driver that only runs a binary with zero SDK output is not acceptable — reports live and die by SDK coverage.

### III. Short-running commands
`eventually_*` and `finally_*` commands sleep 15 s to let the system settle, then do a single bounded validation, then exit. No 12-hour polling loops. `serial_driver_*` and `parallel_driver_*` complete in minutes, not hours. Antithesis's built-in "All commands were run to completion at least once" property enforces this.

### IV. Duration-robust
Templates must work at `duration=1h` just as well as `duration=3h`. Findings that only appear at short durations because a command didn't get scheduled are composer-structure bugs, not coverage artifacts.

### V. Realistic workload over synthetic volume
We prefer a small amount of *real application traffic* (goal-driven agents using a real dApp) over large amounts of random transactions. Antithesis's value comes from assertions on real behavior; random bytes give the report nothing to score.

### VI. Bisect-safe commits
Every commit on a feature branch compiles, its tests pass, and the testnet comes up via `just smoke-test`. Use the additive-then-remove pattern for refactors.

### VII. Image tag hygiene
Every `ghcr.io/cardano-foundation/cardano-node-antithesis/<name>:<tag>` in compose must resolve to a commit in the history, with a matching `components/<name>/` directory at that commit. `publish-images` rebuilds and pushes on every PR.

## Additional Constraints

### Custom testnet boundaries
No workload may depend on mainnet-specific genesis, mainnet SPOs, or external oracles we cannot fake locally. Every dependency must be deployable on a private testnet started from scratch via `just up`.

### Minimal sidecar image
The sidecar image carries only coreutils + bash + jq + cardano-cli. Shell composer commands must avoid `grep`, `awk`, `timeout`, and any other tool not explicitly packaged. Use `jq` for parsing and coreutils for everything else.

### Composer smoke-tests run locally before every push
Every composer command must be executable locally via `docker compose -f testnets/... exec <container> /opt/antithesis/test/v1/<template>/<cmd>` and exit 0 on a healthy cluster. This validates that the image has what the command needs before paying for an Antithesis run.

### Hard gate: findings_new <= baseline
A PR that changes the composer, a sidecar, or the testnet compose must run an Antithesis duration=1h on the branch before merge. If the run's `findings_new` is above the baseline on main (accounting for stable finding IDs that were already there), the PR does not merge.

**Declared-property exemption.** A new finding does not count against the gate when it is produced by a property the PR itself intentionally adds, provided all of the following hold: the PR body names the property and states that its firing is the success signal; the failure it exposes is pre-existing (evidenced by an upstream issue or an event-stream search of a baseline run) rather than introduced by the PR; the property is proven both ways (a seeded or live failing case, and a clean passing case); and every other finding still satisfies `findings_new <= baseline`. Rationale: the gate exists to stop PRs *introducing* regressions; a property that *reveals* an existing failure is the observability this harness is for, and blocking it institutionalises blindness. The exemption is per-declared-property, never blanket — an undeclared new finding still blocks the merge.

## Development Workflow

### Ticket discipline
Every feature starts with a GitHub issue. Every issue goes through `/speckit.specify → /speckit.plan → /speckit.tasks → /speckit.implement`. No implementation without a spec and task list.

### Worktrees
Each branch lives in its own worktree under `/code/cardano-node-antithesis-<slug>`. The main repo stays on `main`. Delete the worktree when the PR merges.

### Bumping an image
When a PR modifies a component's source, the PR MUST also bump the component's tag in `testnets/cardano_node_master/docker-compose.yaml` to a commit SHA from the branch, so that `publish-images` builds and pushes the new image and Antithesis pulls the right thing.

### Verify-before-merge
For every PR: push, wait for `publish-images` green, trigger an Antithesis duration=1h run on the branch via `gh workflow run cardano-node.yaml --ref <branch>`, compare findings against main's baseline, then merge via `mcp__merge-guard__guard-merge` with `mergeMethod: rebase`.

## Governance

Constitution supersedes all other practices on this repo. Amendments require:
- A PR that updates this file.
- An updated entry in the `Version` / `Last Amended` footer.
- Explicit call-out in the PR description of what changed and why.

All PRs must verify compliance in the PR description by checking that each touched principle still holds.

**Version**: 1.0.0 | **Ratified**: 2026-04-24 | **Last Amended**: 2026-04-24
