# M2 — current state receipt

## Operator-directed delivery reset — 2026-09-07

Read `delivery-plan.md`: first real run by Sep 9 14:00Z, working daily path
by Sep 11 14:00Z, verified delivery by Sep 14 14:00Z. The previous ticket-order
plan is superseded. Outcome remains 0/7, not delivered. NOTE-009 routes the
new priority through the existing epic owner; no new merge/launch/spend grant.
The public wiki is updated to the reset; its full-assurance dependency chart
is explicitly not this week's implementation order. NOTE-009 acknowledged
2026-09-07T13:46:24Z; concrete execution handback remains pending.

## Prior product evidence (not a fresh run census)

Reconciled 2026-09-07T11:55:50Z. Team: **RUNNING**. Outcome: **0/7**
unattended successful days; no M2 Amaru Antithesis launch yet.

The canonical grouped story map and dependency-stage Gantt are published at
https://github.com/cardano-foundation/cardano-node-antithesis/wiki/M2-State,
commit `80204f4b3f7333ed33298a23c3cd5e2b7293273c`. Page SHA-256:
`649ad46ae557ee6ed05d0f98519d22d453bb8adccee8c74bf74268c7beae49d2`.
Register SHA-256:
`075e3399460717ad95d544ebf1e42d848a2e80c1b5d0f6a6f3cce26fd14ce596`.
The reset's 11-story/three-group page passed the deterministic renderer and
exact-byte drift check. Chart structure is unchanged from the earlier rendered
version; no new product run evidence is claimed.

## Immediate edge

- cna main: `6711c4ab8fe02f6418897b73bf42ca41e6efa697`.
- PR #239: merged from head
  `56f3bb3d1fab738311d62e2307d2df51a39d91b0`; it removes the known
  observation-window false negative but does not prove a green nightly.
- Next Daily Amaru cron: 2026-09-08T04:17Z, expected GitHub delivery around
  04:27–04:31Z. Epic owner `%432` reads it; nobody reruns or fires it.
- Bootstrap PR #113: OPEN at
  `0fa91d18e98e6593079012135df8b72e61a337eb`, all three checks green.
- `t-unchanged-head`: active inside cna#205; the desk supervises only `%432`.

## Separate decision

Testnet schedule `34095717978` completed Antithesis run
`e42bb2a0f5f755977aa874789d040e9b-60-7` for 180 minutes with 68/69
properties passing. The only failure is `Recent software version provided`
with 12 stale-image counterexamples. Issue #236 / PR #238 disposition remains
the operator's; PR #238 is OPEN/DRAFT at
`b931bd429af37716419f76f8fadcfed9759f3824` and must not be mistaken for a
merge-ready implementation.

## Recovery identities

- M2 desk: `amaru:1 ms2-amaru-routine`, pane `%694`.
- Immediate child: `amaru:2 cna-e205-lane`, pane `%432`.
- Child resume SHA-256:
  `6247939c67e08be37851ba8806db703657955a3af57308e737323b01f5247e5a`.
- Child map SHA-256:
  `67068643aa88b996bdf566a99487f46e209a90341bf9ea01596d77d43592b496`.
- Lane-operations predecessor `%308`: absent; redundant role retired.
