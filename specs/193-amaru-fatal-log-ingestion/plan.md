# Implementation Plan: Score fatal Amaru container logs

**Branch**: `fix/amaru-fatal-log-ingestion` | **Date**: 2026-07-28 | **Spec**: [spec.md](spec.md)
**Input**: GitHub issue #193 and approved design research in [research.md](research.md)

## Summary

Extend tracer-sidecar with an optional plain-line Amaru input that normalizes
per-relay output into the existing event/rule pipeline. When configured, the
sidecar declares a required route-liveness property plus an invariant that
fails on either accepted fatal consensus signature.

In `cardano_amaru`, each relay writes stdout/stderr directly to a per-relay
regular file on a shared volume. A supervised `tail -F` mirrors that file back
to container stdout. The assertion service mounts the volume read-only. The
regular-file primary removes SIGPIPE and pipe-backpressure coupling between
Amaru and the mirror.

## Technical Context

**Language/Version**: Haskell 2010 on GHC 9.6; POSIX `/bin/sh` in the pinned Amaru image
**Primary Dependencies**: existing `aeson`, `async`, `bytestring`, `text`, `time`; Docker Compose
**Storage**: two append-only regular files on a named Docker volume
**Testing**: Hspec, Nix-built tracer-sidecar test derivation, Docker Compose smoke, one-hour Antithesis run
**Target Platform**: Linux containers in local Docker and Antithesis
**Project Type**: event-processing sidecar plus testnet deployment configuration
**Performance Goals**: line-at-a-time processing; combined three-hour log growth normally 4-6 MB
**Constraints**: no Docker socket; no Amaru logging change; mirror death cannot kill or wedge Amaru; `amaru-consumer-seed` pin untouched
**Scale/Scope**: two relay files, three-hour runs, conservative 250 MB burst-growth bound

## Constitution Check

### Pre-design

- **I Composer-first workload**: PASS — no new workload or composer command.
- **II SDK instrumentation**: PASS — input liveness and fatal invariant are
  both explicit scored properties.
- **III Short-running commands**: PASS — no composer commands or polling
  validators are introduced.
- **IV Duration-robust**: PASS — file discovery and tailing do not depend on
  scheduling duration; growth is measured for three hours.
- **V Realistic workload**: PASS — the route consumes real Amaru output.
- **VI Bisect-safe commits**: PASS — code/tests land together, then deployment
  wiring pins that preceding code commit.
- **VII Image tag hygiene**: PASS — compose references the preceding code
  commit, which exists at `components/tracer-sidecar/`.
- **Custom testnet boundary**: PASS — all inputs are local named volumes.
- **Minimal sidecar image**: PASS — no sidecar shell dependency is added.
- **Hard gate**: REQUIRED — launch the one-hour Antithesis run exactly once,
  compare its findings with baseline, and do not shop for a cleaner run.
  Detector implementation can complete, but the PR remains draft/not-ready
  pending the parent-owned governance decision.

### Post-design

All design checks remain PASS. The current local image-command discrepancy is
tracked as #196; the final Nix-built image has the entrypoint contract expected
by compose. This ticket neither weakens nor claims an exception from the
repository's no-new-findings gate. Because that gate cannot distinguish a
newly introduced regression from a newly exposed pre-existing failure, final
readiness is explicitly handed to the parent for governance resolution.

## Project Structure

### Documentation

```text
specs/193-amaru-fatal-log-ingestion/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── amaru-log-event.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source and deployment

```text
components/tracer-sidecar/
├── README.md
├── src/
│   ├── App.hs
│   └── Cardano/Antithesis/
│       ├── LogMessage.hs
│       └── Sidecar.hs
└── test/
    └── Spec.hs

testnets/cardano_amaru/
└── docker-compose.yaml
```

**Structure Decision**: Reuse the existing tracer-sidecar package and rule
engine. Do not add a collector service, dependency, or general-purpose Docker
logging layer.

## Event and rule design

- Add an `AmaruStdout` payload to the existing log-message model.
- Provide a deterministic adapter from ingestion time, relay filename, and raw
  line to the existing generic event, preserving the normative evidence fields
  in [contracts/amaru-log-event.md](contracts/amaru-log-event.md).
- Read optional `AMARU_LOG_DIR` in `App.main`.
- Generalize the existing file-following seam only as far as needed to discover
  fixed `amaru-relay-[12].log` files and process appended lines.
- Pass an Amaru-ingestion-enabled flag into `mkSpec`; when false, neither new
  property is declared.
- When true, add:
  - `sometimes "amaru stdout observed"` on any `AmaruStdout`;
  - `alwaysOrUnreachable "no fatal amaru consensus logs"` rejecting either
    exact signature.
- Keep existing cardano-tracer rules and golden output unchanged when ingestion
  is disabled.

## Routing design

For each Amaru relay command:

1. Create the shared log directory and its per-relay regular file.
2. Start a background supervisor that launches `tail -n 0 -F` to the
   container's original stdout, records the active mirror PID, waits for exit,
   and restarts after one second.
3. `exec /bin/amaru node run ... >>relay.log 2>&1`.

Amaru remains PID 1 and owns a regular-file descriptor. The mirror reads the
file; it is not on Amaru's writer path. Mount the new volume read-write into
both relays and read-only into tracer-sidecar, and set `AMARU_LOG_DIR`.

## Slices

### Slice 1 - sidecar ingestion and scored properties

**Owned files**:

- `components/tracer-sidecar/src/App.hs`
- `components/tracer-sidecar/src/Cardano/Antithesis/LogMessage.hs`
- `components/tracer-sidecar/src/Cardano/Antithesis/Sidecar.hs`
- `components/tracer-sidecar/test/Spec.hs`
- `components/tracer-sidecar/README.md`

**RED**: Add focused tests for ordinary, both fatal signatures, disabled
configuration, and appended-file ingestion. Run them before implementation and
preserve the failing raw output.

**GREEN**: Implement the adapter, watcher, conditional declarations, and
documentation. Run focused tests, formatting/lint, then `./gate.sh`.

**Commit**: `fix(tracer-sidecar): score fatal amaru logs`

### Slice 2 - fault-contained compose routing and image pin

**Owned file**:

- `testnets/cardano_amaru/docker-compose.yaml`

**Dependency**: Slice 1 commit is pushed and its hash is used as the
tracer-sidecar image tag.

Implement the shared volume, regular-file primary, supervised stdout mirror,
read-only sidecar mount, configuration, and image pin. Preserve the
`amaru-consumer-seed` image line exactly.

Verify compose resolution, build/load the Slice 1 image for local proof, rerun
the mirror-kill proof against the final construction, prove both live ingestion
directions, and run the mechanical gate. Push only after navigator approval and
orchestrator verification.

**Commit**: `fix(cardano_amaru): route amaru logs to sidecar`

## Final verification

1. Wait for all PR checks, including the standard `cardano_amaru` compose
   smoke, to finish green.
2. Independently rerun the final gate with raw evidence capture.
3. Verify compose diff leaves the forbidden consumer-seed pin unchanged.
4. Verify the final live route and mirror-kill evidence from raw files.
5. Launch exactly one one-hour Antithesis run on the branch, confirm both
   properties surface, and record `findings_new` against the accepted main
   baseline. Never retry to select a clean schedule.
6. Refresh the human-readable PR body, including the incidentally-correct
   Nix-image pairing for #196.
7. Run the finalization audit and leave `gate.sh` plus the PR's draft/not-ready
   state in place. If the fatal property fires, report it as successful detector
   evidence and hand the not-ready PR to the parent. If it does not, state that
   the deterministic proofs—not the clean schedule—prove the detector. In
   either case, await the parent-owned governance call; do not merge or close.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Fatal property passes vacuously | Required `amaru stdout observed` property |
| Mirror death sends SIGPIPE or causes backpressure | Amaru writes a regular file; mirror is a separate reader |
| Mirror dies permanently | Supervisor restarts it; kill proof checks recovery |
| Log volume fills | Measured 4-6 MB expectation and <250 MB sustained-burst bound |
| Sidecar starts before relay file | File watcher discovers files created later |
| Sidecar restart rereads a fatal line | Failure remains failing; first-failure suppression resets only per process |
| Wrong image runs | Compose pin references Slice 1 commit; publish-images gate |
| Sibling #192 compose race | Diff-police and preserve `amaru-consumer-seed` line byte-for-byte |
| Local/deployed image command mismatch | #196 owns discrepancy; final Nix image supplies expected entrypoint |
| A real upstream fatal becomes a new finding | Run once, report it as detector success, keep the PR not-ready, and hand governance to the parent |
