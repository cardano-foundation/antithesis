# Tasks — Issue 202

## Slice 1 — Add and wire the contract check

- [X] T202 Implement the dynamic producer-image checker; prove seeded drift
  and tag-only failures; prove the clean pass; wire the checker into the
  tracked local gate and PR-triggered workflow; land one reviewed bisect-safe
  commit.

## Orchestrator finalization

- [ ] Independently replay both RED controls and retain raw logs.
- [ ] Independently run the clean checker and tracked gate.
- [ ] Verify the PR workflow reaches the checker and retain its passing log.
- [ ] Record complete evidence in the human-readable PR body.
- [ ] Obtain Milestone 1 desk authorization through the Q/A file protocol.
- [ ] Merge only after explicit authorization is recorded.
- [ ] Launch the closing 60-minute Antithesis run from final `main`.
- [ ] Deliver full per-property accounting: #1098 signatures absent, only
  #1104 and #140 expected red, every other red treated as a genuine finding.
