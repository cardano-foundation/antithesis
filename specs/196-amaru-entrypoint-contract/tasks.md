# Tasks — Issue 196

## Slice 1 — Live compose/image entrypoint contract

- [x] T1961 Implement the stable Compose/image entrypoint command with
  digest-aware image input, exact expected argv, zero-target rejection, and
  non-vacuous runtime evidence.
- [x] T1962 Prove the check against the real Docker boundary in both directions,
  including successful container start and a seeded entrypoint mismatch.
- [x] T1963 Wire the focused command into the shared local/hosted
  `cardano_amaru` smoke path without changing unrelated testnet behavior.
- [x] T1964 Record the historical local-versus-Antithesis image identity answer
  and publish the command, input, output, and #208 release contract.

## Ticket-owner finalization evidence

The owner retains raw baseline, RED/GREEN, restoration, full-smoke, commit,
push, PR metadata, and current-head CI evidence under the runtime root. These
are acceptance records, not additional implementation tasks.
