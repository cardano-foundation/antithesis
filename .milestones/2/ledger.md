# Milestone 2 — Amaru tested routinely under fault injection

Home: cardano-foundation/cardano-node-antithesis milestone #2. Durable state:
the depth-one `milestones` branch. Desk: tmux `amaru:1 ms2-amaru-routine`, pane
`%694`, runtime `/tmp/ms-cardano-node-antithesis-2/`.

Public product view: https://github.com/cardano-foundation/cardano-node-antithesis/wiki/M2-State
at wiki commit `80204f4b3f7333ed33298a23c3cd5e2b7293273c`. The raw story
register SHA-256 is
`075e3399460717ad95d544ebf1e42d848a2e80c1b5d0f6a6f3cce26fd14ce596`;
the generated page SHA-256 is
`649ad46ae557ee6ed05d0f98519d22d453bb8adccee8c74bf74268c7beae49d2`.
The register contains 11 stories in three groups and maps every open issue
currently assigned to the GitHub milestone: `#205`, `#208`, `#207`, `#206`,
and `#140`.

The desk performs asks, answers and sweeps only. Its only immediate child is
cna#205 epic owner `%432`; it never directs ticket owner `%430`, commit owner
`%675`, or any other grandchild. Agents never publish as the operator, never
post upstream issues/comments, and never force a nightly run.

## Outcome test — frozen

Once per UTC day, when Amaru main changed, the controller must bump Amaru,
build and publish its image, repin the exact digest, and launch a one-hour
fault-enabled Antithesis run without a human. The harness covers the current
interface or alarms and cannot pass vacuously. Missing, failed and partial
runs are loudly distinct; declared reds remain declared until a verified fix
and recorded decision clear them. Every new red becomes an operator-ready
packet within 24 hours; external human relations remain the operator's alone.

Milestone completion requires seven consecutive unattended successful daily
observations followed by an independent outcome audit against the published
artifact and the complete contract registry. Current streak: **0/7**. No M2
Amaru Antithesis launch has occurred. Reforecast only after a real full-path
scheduled success establishes day 1.

## State — ACTIVE 2026-09-07T11:55:50Z

M2 ownership was restored by the operator in pane `%694`. The desk read the
previous depth-one snapshot `f79fb290e6396498fbebc1962b29588a8a34bebb`,
then reconciled it against the current epic journal, child-authored map/resume,
tmux topology, GitHub state and Antithesis REST evidence. The 2026-08-23
capacity queue, stopped-runner boundary and unmerged PR #96 state are
historical and superseded; do not resume from them.

The only immediate child is cna#205 epic owner `%432`, window
`amaru:2 cna-e205-lane`. Its current child-authored resume SHA-256 is
`6247939c67e08be37851ba8806db703657955a3af57308e737323b01f5247e5a`;
its map SHA-256 is
`67068643aa88b996bdf566a99487f46e209a90341bf9ea01596d77d43592b496`.
The redundant lane-operations role from handoff SHA-256
`676a1d91aa05540cdf11c4b3355323624a76f2bc9fc75c44cb3898561a51cc80`
is retired, predecessor pane `%308` is absent, and no successor `HANDOFF-ACK`
is owed. The 2026-09-08 scheduled Daily Amaru read duty remains with `%432`.
Future lane seats get their own runtime roots and journals; they never append
to the epic owner's `STATUS.md`.

Current cna main is exact
`6711c4ab8fe02f6418897b73bf42ca41e6efa697`, committed 2026-09-07T08:34:18Z
by merging PR #239 head
`56f3bb3d1fab738311d62e2307d2df51a39d91b0`. The last five scheduled Daily
Amaru controller runs are failures on the old head
`fe039ac5582081297b38709a6862083cc2fb6c00`: `34083416756`, `34011582013`,
`33944613558`, `33837021124`, and `33718650074`. Run `33944613558` produced
bootstrap PR #113 head
`0fa91d18e98e6593079012135df8b72e61a337eb`, whose Build Gate, Live Bootstrap
Producer and deploy checks are all green. The controller falsely stopped
observing before the sequential Live Bootstrap Producer completed; PR #239
removes that cause but does not prove the next nightly green.

The next controller cron is 2026-09-08T04:17Z; recent GitHub schedule delivery
has landed around 04:27–04:31Z. Because main moved from `fe039ac...` to
`6711c4ab...`, a fresh attempt is expected, but that is a prediction only.
Read the scheduled run after completion; never fire or rerun it.

Inside the epic, `t-unchanged-head` is active from base `6711c4ab...`. At the
milestone level its contract is visible but its workers are not control
surfaces: every successful exit-zero outcome must leave the next night
distinguishable from a failed attempt, while genuine failures stay red, and
the check must quantify over the discovered extent rather than a hardcoded
pair.

## Separate scheduled testnet red — issue #236 decision

Latest `cardano-node.yaml` schedule run `34095717978` on old head
`fe039ac5582081297b38709a6862083cc2fb6c00` submitted Antithesis run
`e42bb2a0f5f755977aa874789d040e9b-60-7`. It completed the full 180 minutes:
68/69 properties passed. The only failure was `Recent software version
provided`, with 12 concrete stale-image counterexamples. No new functional
failure is evidenced by that run.

Issue #236 / PR #238 is the intended Cardano Node image-rotation lane. Live
GitHub state verifies PR #238 is OPEN/DRAFT at
`b931bd429af37716419f76f8fadcfed9759f3824`, with only `Daily Amaru contract
dry run` failing in run `33765114074`. The epic/operations evidence reports
that this PR is planning-only and that the red is a structural foreign-slice
fence inherited from the merged observation work, not a #238 product failure.
The operator owns whether #238 is disposed, re-cut, or resumed with a fresh
standalone ticket owner. The desk does not merge or restart it.

## Priority and convergence

Operator reset 2026-09-07: **delivery-plan.md is the governing implementation
priority**, superseding the previous whole-ticket serial order. First real
Amaru run by Sep 9 14:00Z; daily scheduling and failure handling by Sep 11
14:00Z; verified unattended delivery by Sep 14 14:00Z. These are delivery
checkpoints, not predicted successful observations or milestone completion.

One accountable delivery owner remains `%432`. NOTE-009 was acknowledged
2026-09-07T13:46:24Z in its own journal; execution handback remains pending.
NOTE-009 directs it to recover
the actual operation sequence, connect the smallest missing pieces, identify
authority blockers immediately, and proceed beyond planning. Reuse work in
bootstrap #75/#79 and cna#207/#206 without requiring broad ticket closure
before the real integrated path is exercised. Preserve active work and evidence.

Keep real-image compatibility, progress, exact digest identity and loud results.
Defer comprehensive #208/#110 frameworks, unrelated #140/#236 work, general
gate cleanup and release packaging. Keep #232/#233's missing-run obligation in
the smallest adequate form. All deferred requirements stay OPEN for full M2.
The Sep 8 scheduled read stays with the epic but is not a substitute for
implementation. No new launch, rerun, merge or spend authority is granted.

See delivery-plan.md for acceptance and missed-checkpoint rules. The full
seven-day streak and independent audit remain separate, unsatisfied conditions.

## Parked decisions and honest gaps

- **D-M2-236 — operator:** dispose, re-cut or resume PR #238/issue #236. The
  current PR is not an implementation and is not merge-ready.
- **Upstream Amaru custom-network fix — operator publication:** the draft may
  be prepared locally, but agents do not send it or contact upstream humans.
- **Epic artifact release:** the daily controller is repository workflow code;
  no separately published epic artifact exists. Record this as open, not
  satisfied.
- **Mode-B controller exits:** the 2026-08-30/31 5–7 second class has not
  recurred since, is unproven in both directions, and is not silently closed.

## Live owner topology

| window / pane | owner | milestone-visible state |
|---|---|---|
| `amaru:1 ms2-amaru-routine` `%694` | M2 desk | ACTIVE; asks/answers/sweeps only |
| `amaru:2 cna-e205-lane` `%432` | cna#205 epic owner | ACTIVE; owns scheduled read and its child topology |

Pane `%308` is absent and its redundant lane role is retired. `%430` and
`%675` are epic descendants and are intentionally not milestone control
surfaces. The exact child-authored fragment is copied byte-for-byte to
`resume/e205.md`; `session.md` records its digest and replay boundary.
