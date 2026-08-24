# Data model — Issue 232

Artifact ceiling: 3,500 bytes and 90 lines.

## D232-1 — observation interval

- `observed_at`: watchdog-owned UTC instant;
- `day`: the previous UTC calendar date;
- `start`: inclusive `dayT00:00:00Z`;
- `end`: exclusive next-day `T00:00:00Z` and already past at evaluation.

Production derives all four from its own clock. No producer value or external
day override participates.

## D232-2 — canonical receipt observation

- source: repository plus fixed receipt issue cna#210;
- comment identity: stable numeric ID and public HTML URL;
- marker: exact leading `<!-- daily-amaru receipt -->`;
- claimed day: exact `day=YYYY-MM-DD` field;
- created time: GitHub-owned `created_at`;
- page coverage: complete or failed.

A match requires marker, claimed day equal to D232-1 day, and creation time in
`[start,end)`. Presence is a non-zero set of matching comment identities.
Property fields, stage/outcome meaning, run data, and body text not needed for
identity are not retained in evidence.

## D232-3 — watchdog verdict

Exactly one of:

- `PRESENT`: D232-2 is complete and has a positive match count;
- `ABSENT`: D232-2 is complete, has zero matches, and D232-4 reconciliation
  succeeded;
- `ERROR`: clock, read, pagination, parse, or reconciliation did not complete.

`PRESENT` exits zero. `ABSENT` and `ERROR` exit non-zero with distinct evidence.

## D232-4 — canonical incident

- repository issue identity and stable body marker;
- lifecycle: open or human-closed;
- history: unique observation-day rows with verdict and stable watchdog run
  link when available;
- recovery notes: optional unique present-day rows;
- last action: opened, updated, unchanged, or recovery-recorded.

At most one open marked incident may exist. Repeating a day does not duplicate
its history. Distinct missing days accumulate. Automation never transitions
the issue to closed. A human-closed prior incident is historical; a later
absence may open a new marked incident without editing the closed record.

## D232-5 — public verdict evidence

- exact repository revision, observation day/interval, D232-3 verdict;
- receipt count and stable matching IDs for `PRESENT`;
- canonical incident ID and reconciliation action for `ABSENT`;
- named failing boundary for `ERROR`;
- explicit proof-control and external-effect counts in proof mode.

Secrets, authorization material, signed URLs, and unrelated comment bodies are
invalid evidence fields.
