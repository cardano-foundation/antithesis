# Milestone 1 — Amaru observed under fault injection — **COMPLETE 2026-07-29**
Home: cardano-foundation/cardano-node-antithesis milestone #1 · ledger: `milestones` branch, depth 1.
Closed by outcome audit at the ms1 desk. Remnants transferred to ms2 (Amaru tested routinely under fault injection, window ms2-amaru-routine).

## Outcome audit — each clause against named evidence
Test (frozen day one): 1h run on current upstream amaru main; fatal-logs property scoring; every red real and owned; consensus-death signature absent (post pragma-org/amaru#1098) or RED — never silent. Operator addendum: completion requires a closing run on FINAL main.

1. **1h runs on current upstream main** — three 60m fault-injection runs:
   ab36fa1b…-56-17 (pin e706976, pre-fix), 33fbed3c…-56-17 (pin 437ff6c,
   fix adopted, merge 12368b3), 0ed9a9d1…-56-17 (FINAL main fa39820,
   contracts CI-enforced). ✓
2. **Fatal-logs property scoring, proven both directions** — 48
   counterexamples on the broken pin (able to fail); Passing 0 cex on the
   fixed pin and closing run WITH positive control (same instrument
   returns 50/50 on retained broken-pin evidence — able to see). ✓
3. **Every red real and owned** — across all three runs the only reds:
   pragma-org/amaru#1098 (declared, exempted via cna#198, never
   suppressed), pragma-org/amaru#1104 (FOUND BY THIS HARNESS, filed with
   evidence + magnitude follow-up), cna#140 (owned artifact). Panic census
   in runs 2–3: single source location. No unowned red ever shipped. ✓
4. **Signature absent-or-RED, never silent** — RED and scored pre-fix;
   ABSENT with control post-fix, twice. ✓
5. **Closing run on final main** (operator ruling) — 0ed9a9d1 on fa39820:
   31/34, reds only #1104+#140, runtime image identity verified in-run. ✓

## What shipped
- Epic #55 (observability) closed outcome-audited: fatal-log scoring (cna#194), findings-gate exemption (cna#198), cli-mock-honesty CI-enforced with drift-red proof (#70/PR71).
- Upstream pin current (amaru-bootstrap#68→PR69, #67→PR74; fix #1098 adopted); producer image digest-locked (cna#195/PR199, #200/PR201) and contract CI-ENFORCED (cna#202/PR203).
- Upstream contributions: pragma-org/amaru#1102 (peer-snapshot offline defect), pragma-org/amaru#1104 (rewards panic — new bug found by fault injection), fix verification A/B for #1098.
- Registry (registry.md): every contract enforced or owned; zero unaddressed NONE.

## Remnants → ms2
#140, #196, #36, #16, #54 (blocked upstream), watch pragma-org/amaru#1104, llm-settings PR #53 (operator review), operator GPG unlock (host item).
