# M2 recovery plan — first run, then routine operation

Operator-directed reset, 2026-09-07. Accountable owner: M2 desk. Delivery owner:
cna#205 epic owner. This replaces the previous implementation priority order,
not the retained evidence or the milestone's final assurance requirements.
Deadline: 2026-09-14T14:00Z. First-run checkpoint: 2026-09-09T14:00Z.

## What we are delivering this week

An existing daily schedule detects a changed pragma-org/amaru main, builds and
publishes its image, pins that exact digest in the existing Amaru harness,
launches one hour of fault-enabled Antithesis testing, and retains a truthful
terminal result with per-property outcomes. No person moves the artifact,
merges a bump, edits a pin, or launches the next stage during the daily path.
Unchanged days are explicit successful no-ops, not test runs. Failed or missing
stages are visible failures, not successes or reasons to silently reuse an image.

Automation working is separate from Amaru passing every property. A real Amaru
failure must be retained and reported; it does not authorize suppression or a
claim that the milestone's successful-day streak advanced.

## Only three delivery checkpoints

| Due (UTC) | Observable result | If absent |
|---|---|---|
| Sep 9, 14:00 | First real one-hour Amaru run through the exact image-to-harness path; Amaru process/progress and property observations evidenced, run ID and result retained. Scheduled/unattended versus operator-authorized smoke explicitly labelled. | Stop expansion and report the exact failing operation, evidence, owner and smallest correction or missing permission. Reassess the week; no replacement planning cycle. |
| Sep 11, 14:00 | The same path is driven by the existing daily schedule without intermediate human action; changed, unchanged, failed and duplicate-trigger paths tested. | Name the specific remaining manual step or failure. Do not describe a script or dry run as unattended delivery. |
| Sep 14, 14:00 | Reviewed changes are deployed, a real scheduled changed-input run has completed end to end, the next scheduled observation behaves correctly, and missing/failed/partial results are loud with retained property results. | Report NOT DELIVERED with the exact remaining gap. No deadline extension or watered-down completion label without the operator. |

The first run is the immediate objective; the dates are latest checkpoints,
not permission to wait. If no upstream change occurs in the verification
window, unchanged receipts alone cannot satisfy the changed-input test. Return
that evidence gap and the smallest operator-authorized test option promptly.

## Start now: recover the working sequence, then automate its joins

The epic owner produces one compact execution sheet from existing scripts,
accepted work and retained live evidence: each operation's actual command or
workflow entry point, input, output, responsible repository, and status
(real execution / inspection only / missing). Start from the manual operation
sequence the operator says is achievable in an hour; do not assume we have
already reproduced it. Ask only for an irrecoverable missing step, not a new
requirements interview. In the same handback, identify the next operation that
can run under current authority and every merge, credential or launch blocker.

Use the existing controller, image build/publication and Amaru testnet. Repair
or connect the smallest missing pieces, then exercise the real path before
adding generalized machinery. An unmerged candidate may supply reusable code,
but never inherits acceptance or provenance from another SHA.

Current recorded baseline: cna main
6711c4ab8fe02f6418897b73bf42ca41e6efa697 (PR #239 merged); bootstrap PR #113
0fa91d18e98e6593079012135df8b72e61a337eb has three green checks. These are
Sep 7 evidence, refresh before reuse. No full-path outcome is established;
streak remains 0/7. The Sep 8 04:17Z controller observation remains assigned
to the epic owner, but waiting for it is not the implementation workstream.

## Keep, narrow, defer

- Keep image/source/digest identity across the real consumer boundary; real
  Amaru startup and chain progress; fault-enabled duration and run identity;
  non-empty, complete property observations; bounded failure/timeout handling;
  secret safety; no duplicate paid launches; no suppressed red results.
- Narrow bootstrap #75/#79 to the handoff actually consumed by this path,
  cna#207 to repin-and-launch, and #206 to durable honest results. Reuse their
  work; whole-ticket closure is not a prerequisite for exercising a sound
  integrated slice. The epic owns code and ticket slicing, not the desk.
- Keep the active t-unchanged-head repair only to the extent needed for daily
  correctness. Preserve its work and frozen evidence; its immediate owner
  checkpoints/re-scopes it through the existing protocol, never by changing a
  running gate or manufacturing acceptance.
- For #208/#110, retain a concrete real-image compatibility/progress check in
  this week's path. Defer the comprehensive interface-census and mutation
  framework, not the obligation to refuse a broken or vacuous run. This is a
  reduced interim delivery, not final satisfaction of the full M2 contract.
- For #232/#233, reuse a suitable existing missing-run alarm or implement the
  smallest one needed for this schedule. No new general monitoring platform.
- Defer #140, separate Cardano Node rotation #236/PR #238, general gate cleanup,
  release packaging and architectural consolidation. If one demonstrably
  blocks the actual Amaru path, return that exact evidence for a bounded fix;
  ticket age or a red unrelated suite is not a dependency by itself.

All deferred items remain open. Nothing is deleted, marked fixed or silently
waived. The old broad milestone remains incomplete until its requirements,
seven successful unattended daily observations and independent outcome audit
are met. A one-week delivery is not MILESTONE-COMPLETE.

## Authority and operating discipline

M2 owns priority and acceptance; the existing epic owns the integrated delivery
and its children. No new management layer or parallel planning programme.
At most one planning handback before an executable next step or one
consolidated blocker. Updates state: last real operation completed, next real
operation, blocker/decision, and remaining deadline risk. No progress percentage
based on documents, panes or ticket counts.

Existing restrictions remain: operator merges; no agent-initiated manual
Antithesis launch/rerun or extra paid run; no upstream issue/comment/contact;
no credential exposure; no destructive cleanup. The plan is not launch or spend
authorization. Identify any such dependency in the first handback, with the
exact target/duration and minimal approval needed. Do not wait until day two
to reveal it. Scheduled operation already authorized remains distinct from a
new manual smoke. This desk contacts only the epic owner.

## Evidence for acceptance

One linked chain: upstream SHA -> image digest/build evidence -> deployed
controller/harness SHA -> schedule event -> Antithesis run ID, actual Amaru
progress and fault configuration -> terminal and per-property results.
Also retain executable controls for stage failure/missing result, unchanged
success after a successful run, failed prior attempt, and duplicate-trigger
prevention. A mocked run, green build, manually moved digest or submitted job
without a terminal result is not the delivered daily capability.
