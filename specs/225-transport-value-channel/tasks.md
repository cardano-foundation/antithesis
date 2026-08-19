# Tasks

Slice `S1` — transport value channel and re-attempt-safe bootstrap proposal.
Bisect-safe as one unit (`plan.md`, "Ordered work").

- [ ] T225-01 Boundary harness: local bare bootstrap remote, extended `gh`
      stand-in, deterministic lock rewriter (`M-225-3`, `functions-model.md`),
      driving the **real** transport with real `git`.
- [ ] T225-02 RED: pollution proof through the real controller and real
      transport at base behaviour, failing with exactly `malformed-candidate-sha`
      (`R-225-1`, INV-225-A3).
- [ ] T225-03 RED: proposal re-attempt proof at base behaviour — a second
      `propose-bootstrap` for the same upstream SHA against an existing remote
      branch fails at the non-fast-forward push (`R-225-2`).
- [ ] T225-04 Value channel: the structural mechanism and `emit` across every
      value-returning operation in `D-225-2` (`R-225-1a`, `R-225-1b`, `R-225-1c`,
      INV-225-A1, INV-225-A2).
- [ ] T225-05 Value-channel census proof: every value-returning operation emits
      exactly its value under noisy external commands (INV-225-A2).
- [ ] T225-06 Proposal classification and the three outcomes: adopt, foreign
      red, fresh create (`R-225-2a`, `R-225-2b`, `R-225-2c`, INV-225-B1..B3).
- [ ] T225-07 Mutants: pollution-restoring, adoption-defeating,
      foreign-accepting, and classification-ordering, each proved to apply and
      to be rejected (INV-225-A3, INV-225-B4).
- [ ] T225-08 Preservation proof: `receipt_keys` and the controller's validation
      regexes unchanged; existing effect censuses still honest; no real launch
      (INV-225-C1..C3).
- [ ] T225-09 Re-base the daily-loop scope fence to this slice's pre-slice base
      and allow-list, keeping the `scope-path-outside-fence` mutant rejected and
      `dry_run_steps_identical` green (INV-225-D1).
