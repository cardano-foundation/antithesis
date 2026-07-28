# Research: Amaru fatal-log ingestion

## Decision 1: shared regular-file route

**Decision**: Each relay writes stdout and stderr directly to its own regular
file on a shared Docker volume. Tracer-sidecar mounts that volume read-only and
tails the files.

**Rationale**: This stays within the repository's existing shared-volume
sidecar pattern, needs no Docker control socket, and does not change Amaru's
logging implementation.

**Alternatives considered**:

- Docker Engine API collector: rejected because it exposes the control socket,
  assumes platform-specific availability, and adds reconnect/API complexity.
- Docker logging driver receiver: rejected because daemon support is unproven
  and it risks breaking the container-output stream Antithesis already indexes.
- Upstream structured logging: rejected because changing Amaru is an explicit
  non-goal.

## Decision 2: regular file is primary; stdout is a supervised mirror

**Decision**: Amaru's descriptors point to the regular file. A background
supervisor runs `tail -F` to mirror new file content to the container's original
stdout and restarts the mirror after exit.

**Rationale**: A FIFO makes Amaru depend on a live reader: if `tee` dies, Amaru
can receive `SIGPIPE`; if the reader pauses while a dummy descriptor keeps the
FIFO open, the pipe can fill and wedge Amaru. A regular file removes both
couplings. Killing or pausing the mirror affects only search visibility during
that interval; scoring continues from the shared file.

**Demonstrated result**: In an isolated fresh compose deployment, the active
mirror was killed while real Amaru ran as PID 1. The mirror PID changed from 12
to 171, Amaru retained the same host PID, the container remained running with
restart count 0, its output descriptor remained a regular file, the file grew,
and a post-restart marker reached Docker logs. The command exited 0.

## Decision 3: normalize plain lines into the existing event pipeline

**Decision**: Add an Amaru-stdout payload to the existing sidecar log-event
model. The adapter supplies ingestion time, `Amaru.Stdout` namespace,
source/host/raw-line evidence, and a non-critical generic severity. The existing
rule engine processes the normalized event.

**Rationale**: This reuses declaration, first-failure suppression, state, and
SDK output without refactoring every existing node-log rule to a new sum type.
The dedicated fatal property carries severity semantics; ordinary Amaru lines
must not accidentally trip the existing cardano-node critical-log property.

## Decision 4: guard against vacuous success

**Decision**: When Amaru log ingestion is configured, declare both:

- required Sometimes property `amaru stdout observed`; and
- AlwaysOrUnreachable property `no fatal amaru consensus logs`.

**Rationale**: The fatal invariant alone would pass if the route silently
disconnected, recreating the defect. The required liveness property makes the
input path itself scored.

## Decision 5: two commits for image hygiene

**Decision**:

1. Land sidecar code, tests, and component documentation.
2. Route compose logs and pin tracer-sidecar to the preceding code commit.

**Rationale**: The image publisher resolves compose tags to commits. A compose
commit cannot self-reference its own hash, so the image source must be a
preceding commit.

## Log growth

Two measured samples bound the three-hour expectation:

- Isolated fresh deployment: 27,695 combined relay bytes over 77 seconds,
  projecting to 3,884,493 bytes over three hours.
- Baseline Antithesis path: 388,368 combined relay bytes over 704 virtual
  seconds, projecting to roughly 6.0 MB over three hours.

The densest observed fatal burst produced 388,368 bytes in 20.7 seconds. If
that burst rate were sustained continuously for three hours, it would be about
203 MB. The plan uses 250 MB as a conservative stress bound.

## Related live-boundary defect

A fresh local deployment of the current `tracer-sidecar:e01ad90` compose/image
pair cannot start the service because Compose replaces a full image `Cmd` with
only the directory argument. The same compose shape worked in a validated
Antithesis deployment, so the local/platform discrepancy is tracked separately
as cardano-node-antithesis#196. This ticket uses the Nix-built image from its
code commit, whose entrypoint contract matches the compose argument.

## One-shot deployment evidence and readiness

The required one-hour Antithesis run is launched exactly once. Retrying until a
schedule omits the known upstream fatal would shop for green and manufacture a
misleading readiness signal. If the new property catches the pre-existing
failure, that is successful detector evidence even though the repository's
no-new-findings gate keeps the PR not-ready. If it does not occur naturally,
the controlled fixture and live-injection proofs remain authoritative. This
ticket neither weakens the gate nor grants itself an exception; the parent owns
the governance escalation and final readiness call.
