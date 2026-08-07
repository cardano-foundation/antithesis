# Tasks

Stable IDs, grouped by slice. A task is checked only after its slice is
audited and accepted by the ticket owner.

## S1 — controller-policy

- [ ] T2151 Deterministic fake transport implementing the full operation
      surface with per-scenario observations and an append-only invocation log.
- [ ] T2152 Controller stage machine with fail-closed exits and
      `CandidateReceiptV1` composition (I215-08, I215-09).
- [ ] T2153 Observation validation for `resolve-upstream` and candidate-form
      validation for `publish-candidate` (I215-01, I215-02 form).
- [ ] T2154 Topology census, equality, and stale-reference rejection over
      Compose-resolved rows; Compose-validation stage (I215-04, I215-05).
- [ ] T2155 Submission-reachability control: exactly one fake submission on the
      complete path, zero in every negative control, and no real-submission
      operation anywhere (I215-06, I215-07).
- [ ] T2156 Test suite with one named scenario per invariant and per negative
      control: wrong ref, wrong origin, malformed and ambiguous observation,
      publish failure, malformed candidate form, revision mismatch, stale
      topology override, missing service, zero census, Compose failure,
      unsupported mode, non-executable transport.

## S2 — github-transport

- [ ] T2161 Bare-remote observation and exact-rev Nix `dockerImage/node` build
      with GHCR publication under the full-SHA tag (R-01, R-02).
- [ ] T2162 Digest read-back and `CandidateRef` emission (I215-02).
- [ ] T2163 Containerized `cardano-node` revision proof (I215-03).
- [ ] T2164 Rendering of `cardano_node_master` into the state directory and
      Compose-resolved topology rows (I215-04, R-10).
- [ ] T2165 Compose validation, fake submission, and receipt persistence
      (I215-05, I215-07, I215-09).
- [ ] T2166 Credential handling confined to the effecting command's environment
      (I215-10).

## S3 — manual-entrypoint

- [ ] T2171 Manual `workflow_dispatch` candidate job running the real path with
      the fake submission transport and publishing the receipt (R-07).
- [ ] T2172 Pull-request job running only the hermetic test suite (R-09).
- [ ] T2173 Operator documentation naming the manual recovery entrypoint, each
      fail-closed stop, and the receipt fields (R-09).
