# Tasks

Slice `S1` — transport value channel and re-attempt-safe bootstrap proposal.
Bisect-safe as one unit (`plan.md`, "Ordered work").

- [x] T225-01 Boundary harness: local bare bootstrap remote, extended `gh`
      stand-in, deterministic lock rewriter (`M-225-3`, `functions-model.md`),
      driving the **real** transport with real `git`.
- [x] T225-02 RED: pollution proof through the real controller and real
      transport at base behaviour, failing with exactly `malformed-candidate-sha`
      (`R-225-1`, INV-225-A3).
- [x] T225-03 RED: proposal re-attempt proof at base behaviour — a second
      `propose-bootstrap` for the same upstream SHA against an existing remote
      branch fails at the non-fast-forward push (`R-225-2`).
- [x] T225-04 Value channel: the structural mechanism and `emit` across every
      value-returning operation in `D-225-2` (`R-225-1a`, `R-225-1b`, `R-225-1c`,
      INV-225-A1, INV-225-A2).
- [x] T225-05 Value-channel census proof: every value-returning operation emits
      exactly its value under noisy external commands (INV-225-A2).
- [x] T225-06 Proposal classification and the three outcomes: adopt, foreign
      red, fresh create (`R-225-2a`, `R-225-2b`, `R-225-2c`, INV-225-B1..B3).
- [x] T225-07 Mutants: pollution-restoring, adoption-defeating,
      foreign-accepting, and classification-ordering, each proved to apply and
      to be rejected (INV-225-A3, INV-225-B4).
- [x] T225-08 Preservation proof: `receipt_keys` and the controller's validation
      regexes unchanged; existing effect censuses still honest; no real launch
      (INV-225-C1..C3).
- [x] T225-09 Re-base the daily-loop scope fence to this slice's pre-slice base
      and allow-list, keeping the `scope-path-outside-fence` mutant rejected and
      `dry_run_steps_identical` green (INV-225-D1).

Slice `S2` — hermetic boundary proof (forward correction on pushed `7c56594`).

- [x] T225-10 Seed every command the boundary proof's operations need and stop
      inheriting the host PATH; the proof's verdict is unchanged under a PATH
      containing only what it seeds (INV-225-E1).
- [x] T225-11 Assert, before any operation runs, that each stand-in resolves
      inside the fixture's own bin, with the assertion shown able to fail
      (INV-225-E2, ratifies CAND-225-3).
- [x] T225-12 Bind every seeded command to a proved-existing binary; die naming
      the command otherwise; ablate all 15 census members and require an
      unchanged verdict (INV-225-E1 v2).
- [x] T225-13 Reject all three substitution modes — dangling symlink, relative
      bin root, fabricated no-op — each with its own mutant (INV-225-E2 v2).
- [x] T225-14 Derive every `BOUNDARY-PATH` count from the executed path, proved
      by a mutant that deletes the verification and reds the run (INV-225-E3).

Slice `S3` — the ablation count must be the ablation.

- [x] T225-15 Derive `census_ablated` from the ablation re-run itself, and prove
      it with a mutant that deletes the re-run and reds the run (INV-225-E3).

Slice `S4` — canonical proof entry, and guards that speak.

- [x] T225-16 Every `x=$(grep -c …)`-shaped guard feeding a `fail` tolerates the
      zero count, so the diagnostic it guards is reachable; forced failures print
      a named `FAIL:` line and a mutant restoring the bare shape reproduces a
      silent death (INV-225-F1).
- [x] T225-17 The dry-run job provisions the dev shell and runs the canonical
      `just ci` entry; the production job's environment is untouched
      (INV-225-F2).
- [x] T225-18 Version the #219/#223 dry-run tamper guarantee from a frozen byte
      image to the canonical entry, keeping its tamper mutant rejected, and add
      the workflow to the slice fence allow-list (INV-225-F3, INV-225-D1).
