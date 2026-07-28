# Tasks: Score fatal Amaru container logs (#193)

**Input**: Design documents in `specs/193-amaru-fatal-log-ingestion/`
**Tests**: RED -> GREEN is mandatory; raw evidence is part of acceptance.

## Slice 1 - sidecar ingestion and scored properties

**Goal**: Turn plain Amaru relay lines into scored events with non-vacuous
route coverage and fatal-consensus failure.

**Independent Test**: Ordinary output hits route liveness without failing the
invariant; each fatal signature fails it; disabled ingestion declares neither;
an appended relay-file line is normalized with exact host and message.

- [ ] T001 [US1] RED: add failing ordinary-line and both-fatal-signature assertion tests in `components/tracer-sidecar/test/Spec.hs`
- [ ] T002 [US2] RED: add failing disabled-configuration and appended-relay-file ingestion tests in `components/tracer-sidecar/test/Spec.hs`
- [ ] T003 [US1] Add the normalized Amaru stdout payload and evidence adapter in `components/tracer-sidecar/src/Cardano/Antithesis/LogMessage.hs`
- [ ] T004 [US2] Add optional relay-file discovery and line following in `components/tracer-sidecar/src/App.hs`
- [ ] T005 [US1] Add conditional `amaru stdout observed` and `no fatal amaru consensus logs` rules in `components/tracer-sidecar/src/Cardano/Antithesis/Sidecar.hs`
- [ ] T006 [US1] Document configuration, event details, signatures, and non-vacuity behavior in `components/tracer-sidecar/README.md`
- [ ] T007 [US1] GREEN: run focused tests, `just format`, `just hlint`, and root `./gate.sh`; commit exactly `fix(tracer-sidecar): score fatal amaru logs`

## Slice 2 - fault-contained compose routing and image pin

**Goal**: Deploy the scored path without coupling Amaru survival to the output
mirror.

**Independent Test**: Fresh compose uses the Slice 1 image; each relay writes a
regular file; killing the active mirror preserves Amaru PID 1 and restart count
and yields a replacement mirror; live ordinary/fatal fixtures reach SDK output.

- [ ] T008 [US2] Route both relay stdout/stderr to per-relay regular files and supervise the stdout mirrors in `testnets/cardano_amaru/docker-compose.yaml`
- [ ] T009 [US2] Add the shared log volume to both relays and mount it read-only with `AMARU_LOG_DIR` in tracer-sidecar in `testnets/cardano_amaru/docker-compose.yaml`
- [ ] T010 [US3] Pin tracer-sidecar to the preceding Slice 1 commit without changing the `amaru-consumer-seed` image line in `testnets/cardano_amaru/docker-compose.yaml`
- [ ] T011 [US2] Prove mirror kill/restart, unchanged Amaru PID 1/restart count, regular-file descriptor, and resumed stdout against the final compose construction
- [ ] T012 [US3] Prove live ordinary and fatal file-to-SDK paths, run compose validation and root `./gate.sh`, and commit exactly `fix(cardano_amaru): route amaru logs to sidecar`

## Finalization - orchestrator-owned verification and PR metadata

- [ ] T013 Verify all GitHub checks including `Compose smoke test` are green and preserve their URLs/results in the evidence record
- [ ] T014 Independently rerun the final gate, audit raw mirror/ingestion proofs, and confirm the forbidden consumer-seed line is unchanged
- [ ] T015 Launch exactly one one-hour `cardano_amaru` Antithesis run, confirm both new properties surface, record `findings_new` against the accepted main baseline, and never retry to select a cleaner schedule
- [ ] T016 Refresh the human-readable PR body including #196's incidentally-correct image pairing; run finalization audit; retain `gate.sh` and draft/not-ready state; report the one-shot result and hand the readiness decision to the parent without merging

## Dependencies and execution order

1. Slice 1 is first because Slice 2 must pin its commit.
2. Slice 2 begins only after Slice 1 is accepted and pushed.
3. T013-T016 begin only after Slice 2 is accepted and pushed.
4. The two behavior slices are intentionally sequential and each produces one
   bisect-safe commit.

## Task-to-requirement coverage

- T001, T003, T005, T007 cover FR-004 through FR-007 and FR-010.
- T002, T004, T005 cover FR-001, FR-003, FR-010, and the late-file edge case.
- T006 covers the documented-path requirement in FR-001.
- T008, T009, T011 cover FR-002, FR-008, and FR-009.
- T010, T012, T013 cover FR-011 and FR-012.
- T015 covers FR-013.
- T010 and T014 cover FR-014.
- Owned-file fences and review cover FR-015.
