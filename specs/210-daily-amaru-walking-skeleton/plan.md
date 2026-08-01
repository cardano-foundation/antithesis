# Plan — Issue 210 daily Amaru walking skeleton

## Technical context

The accepted base is `5336940ae32da29a8ef5a666a3fa8e9d95adc942`.
Fresh intake evidence established:

- the #202 producer checker passes non-vacuously with 3 identical references;
- the merged #196 command starts the exact tracer-sidecar argv and cleans its
  resources;
- `.github/workflows/cardano-node.yaml` is the proven MOOG submission path and
  already accepts testnet, duration, and fault controls;
- the Milestone 1 stock-pin, SHA image publication, digest, repin, and report
  shapes are known;
- no approved short-lived cross-repository credential is configured here.

The desk-approved temporary trunk gate permits this feature PR to land after
named exact-head checks, #202 reachability, epic-owner acceptance, and guarded
merge. It does not permit unattended generated consumer-repin self-merge.

## Architecture

One Bash state machine owns policy. All external effects cross a narrow
transport interface so the same controller can run against deterministic fake
state or the supervised GitHub path.

```text
claim UTC day
  -> resolve exact bare upstream
  -> compare durable last success
     -> equal: UNCHANGED receipt
     -> changed:
        require explicit identity
        -> exact bootstrap proposal/checks/image digest
        -> atomic consumer repin
        -> exact-head named checks + positive #202 census
        -> wait for guarded supervised merge
        -> exact-main one-hour faults-enabled launcher
        -> crude receipt
```

Every arrow is fail-closed. The controller freezes the observed upstream SHA
once and carries exact candidate/integrated SHAs through subsequent calls.

### Planned implementation surface

- `.github/workflows/daily-amaru.yaml`: one daily schedule, PR contract job,
  and manual dry-run entrypoint; production requires an explicit secret input.
- `scripts/daily-amaru.sh`: policy/state machine and stage ordering.
- `scripts/daily-amaru-github.sh`: supervised GitHub transport; prepares and
  observes PRs/checks/receipts but never self-merges the consumer repin.
- `tests/test-daily-amaru.sh`: deterministic transport fixtures and assertions.
- `tests/fixtures/daily-amaru/**`: changed, unchanged, zero/ambiguous,
  duplicate, missing-identity, wrong-head/check, #202 failure, stage failure,
  and fake-launch observations.
- `docs/daily-amaru.md`: operator-visible provisional contract and dry-run.

The pair may consolidate fixture files if the frozen gate proves every named
case. It may not widen into credential configuration, a second orchestration
framework, property reporting, or hardening work.

## Invariants

1. Day claim and duplicate rejection precede mutations and submission.
2. Production mutation is unreachable without a non-empty explicit identity.
3. An exact-head check is accepted only when workflow, check name, head SHA,
   and success conclusion all agree.
4. #202 produces a non-zero census on the exact consumer candidate before
   integration; check presence without retained output is not evidence.
5. The consumer transport has no self-merge operation in production.
6. A launch requires exact merged consumer `main`, all prior releases, a
   recorded launch-attempt guard, duration one hour, and faults enabled.
7. Tests and manual dispatch use the fake launcher; the real workflow dispatch
   is unreachable and invocation count remains zero.
8. Existing #196/#202 implementations and findings semantics are read-only.
9. Every provisional production branch is adjacent to one exact tracked TODO.

## TDD proof contract

RED is the frozen gate on the accepted base: the controller/workflow/tests are
absent. The driver then writes the deterministic test transport first and
observes expected failures before production transport behavior.

GREEN requires the frozen gate to demonstrate:

- distinct changed and unchanged success;
- zero/ambiguous observation rejection;
- missing identity before mutation;
- missing, wrong-head, ambiguous, pending, or failing named checks before
  integration;
- #202 failure and zero census before integration;
- duplicate/same-day, same-SHA retry, and every earlier-stage failure before
  submission;
- exactly one fake submission on the complete path with duration 1 and faults;
- zero real-launch invocations under all test/manual/PR paths;
- all four tracked TODO owners and no anonymous provisional TODO;
- unchanged hashes for #196 and #202 production scripts.

The ticket gate adds shell syntax, ShellCheck, workflow trigger/static policy,
`git diff --check`, and the focused controller suite. It does not launch MOOG.

## Slice 1 — Land the complete thin vertical controller

Topology: `PAIR` because correctness spans durable day state, two repositories,
exact-head CI evidence, integration authority, and a paid live boundary.

- Driver: low-cost qwen, explicitly pinned.
- Navigator: low-cost qwen, explicitly pinned.
- Nested tools: forbidden; no approved external sandbox/attestation launcher.
- Worker roots: fresh; shared issue worktree; no push or merge authority.
- Owned files: only the planned implementation surface above.
- Forbidden: specs/tasks/gate, existing MOOG workflow, #196/#202 scripts,
  Compose, credentials, rules, property/findings code, and other worktrees.

Commit subject:

`feat(ci): add daily Amaru walking skeleton`

Commit trailer:

`Tasks: T2101, T2102, T2103, T2104, T2105, T2106, T2107, T2108`

## Ticket-owner acceptance

After matching driver `COMMIT` and navigator `NAVIGATOR-VERIFIED` events, the
ticket owner will inspect the complete diff and owned-file fence, rerun the
immutable slice gate and ticket gate, verify the original #196/#202 hashes,
stamp T2101–T2108 into the local commit, rerun commit/proof gates, push, refresh
the draft PR, and verify all named hosted checks on the exact accepted head.

The epic owner independently accepts and guarded-merges under the temporary
trunk ruling. Only after exact merged `main` plus dry/negative evidence does the
ticket report `REAL-RUN-READY`; real MOOG remains held until parent release.
