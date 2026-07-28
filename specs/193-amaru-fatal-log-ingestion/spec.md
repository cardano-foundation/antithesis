# Feature Specification: Score fatal Amaru container logs

**Feature Branch**: `fix/amaru-fatal-log-ingestion`
**Created**: 2026-07-28
**Status**: Approved
**Input**: GitHub issue #193 under `lambdasistemi/amaru-bootstrap#55`

## Context

Amaru relays report fatal consensus events to container output, while the
scored assertion service consumes a different structured event stream. This
allows repeated consensus failures to coexist with a green property board when
the process recovers without exiting.

This feature establishes a durable path from each Amaru relay's output into the
scored event stream. It also proves that the path is alive, fails the invariant
for either known fatal signature, remains green for ordinary output, and does
not make Amaru's survival depend on the auxiliary output mirror.

## User Scenarios & Testing

### User Story 1 - Fatal consensus output becomes a scored failure (Priority: P1)

As an Antithesis report reader, I need a fatal Amaru consensus line to fail a
named property even when the relay process and container stay alive, so a green
report means the failure was not observed rather than merely hidden.

**Why this priority**: This is the core visibility gap described by issue #193.

**Independent Test**: Process one ordinary Amaru line and one line for each
fatal signature. The ordinary line must not emit the invariant failure; each
fatal line must emit it with the relay identity and original line attached.

**Acceptance Scenarios**:

1. **Given** an Amaru relay emits `Consensus died`, **When** the line enters the
   scored stream, **Then** the fatal-consensus invariant fails.
2. **Given** an Amaru relay emits `attempted roll back in the future`, **When**
   the line enters the scored stream, **Then** the same invariant fails.
3. **Given** an Amaru relay emits ordinary startup or progress output, **When**
   the line enters the scored stream, **Then** the invariant is declared but
   does not fail.

---

### User Story 2 - The ingestion route is observable and fault-contained (Priority: P1)

As a test operator, I need explicit evidence that Amaru output reaches the
scored stream and that failure of the auxiliary output mirror cannot kill or
wedge Amaru.

**Why this priority**: A fatal-property check that never receives input would
recreate the defect, while a mirror coupled to Amaru could manufacture false
relay failures.

**Independent Test**: Prove a normal relay line reaches the ingestion service,
kill the mirror process, and observe that the same Amaru process remains
running with no container restart while a replacement mirror resumes output.

**Acceptance Scenarios**:

1. **Given** Amaru output routing is configured, **When** any relay line is
   ingested, **Then** a required route-liveness property is hit.
2. **Given** Amaru is running and the output mirror is killed, **When** the
   supervisor replaces it, **Then** Amaru keeps the same process identity, the
   container restart count stays unchanged, and output mirroring resumes.
3. **Given** the mirror is unavailable or paused, **When** Amaru writes output,
   **Then** Amaru writes to a regular file without a pipe dependency and cannot
   receive a broken-pipe signal from the mirror.

---

### User Story 3 - The deployed testnet runs the exact scored path (Priority: P1)

As a maintainer, I need the `cardano_amaru` profile to use the new assertion
image and routing in a fresh deployment, so source-only success cannot be
mistaken for deployed coverage.

**Why this priority**: A property that is absent from the pinned image or a
route that exists only in fixtures provides no production evidence.

**Independent Test**: A fresh testnet deployment uses the new image, passes its
standard smoke test, proves the file-to-assertion boundary in the live
containers, and surfaces the properties in a one-hour Antithesis run.

**Acceptance Scenarios**:

1. **Given** the code commit has been published as an image, **When** the
   `cardano_amaru` profile starts, **Then** both relay logs are mounted into the
   assertion service and the expected properties are declared.
2. **Given** a controlled fatal line is introduced through the live shared-log
   boundary, **When** the assertion service consumes it, **Then** its output
   contains the scored invariant failure.
3. **Given** no fatal signature occurs during a healthy smoke, **When** the
   standard smoke finishes, **Then** the testnet is green.

### Edge Cases

- The mirror exits, is killed, or is paused while Amaru continues producing
  output.
- The assertion service starts before either relay log file exists.
- The assertion service restarts and sees existing relay log files.
- A relay restarts and appends to its existing per-run log file.
- An ordinary line contains the words `consensus` or `rollback` without either
  exact fatal signature.
- A three-hour run includes a short, high-volume fatal burst.
- A fresh local deployment resolves image command metadata differently from a
  deployed Antithesis run; this separate defect is tracked as issue #196.

## Requirements

### Functional Requirements

- **FR-001**: Both Amaru relay output streams MUST reach the scored assertion
  event stream through a documented, persistent route.
- **FR-002**: Existing container-output observability MUST remain available
  after the route is added.
- **FR-003**: The route MUST declare and hit a required liveness property after
  observing any Amaru relay line, preventing a disconnected route from
  appearing green.
- **FR-004**: A scored invariant MUST fail on `Consensus died`.
- **FR-005**: The same scored invariant MUST fail on
  `attempted roll back in the future`.
- **FR-006**: Ordinary Amaru output MUST NOT fail the fatal-consensus
  invariant.
- **FR-007**: A scored failure MUST retain the source type, relay identity, and
  complete original line as evidence.
- **FR-008**: Failure or suspension of the output mirror MUST NOT terminate,
  restart, or block the Amaru process.
- **FR-009**: Killing the mirror during a real Amaru run MUST be demonstrated
  with unchanged Amaru process identity and container restart count, followed
  by successful mirror recovery.
- **FR-010**: The new assertion behavior and the file-ingestion boundary MUST
  have automated tests that are observed failing before implementation and
  passing afterward.
- **FR-011**: The deployed assertion image MUST resolve to a commit in this
  branch's history and contain the new behavior.
- **FR-012**: A fresh `cardano_amaru` compose smoke MUST pass with the final
  routing and image pairing.
- **FR-013**: Exactly one one-hour Antithesis run MUST be launched. It MUST
  surface the new properties, record `findings_new` against the accepted
  baseline, and MUST NOT be retried to select a cleaner schedule. A naturally
  observed fatal-property failure is successful detector evidence for this
  ticket, while final PR readiness remains a separate governance decision.
- **FR-014**: The `amaru-consumer-seed` image pin MUST remain unchanged by this
  ticket.
- **FR-015**: The change MUST NOT modify Amaru's own logging implementation,
  the cluster-fork assertion, or anything in `amaru-bootstrap`.

### Key Entities

- **Amaru output event**: One complete line with its relay identity, source
  type, ingestion time, and original text.
- **Route-liveness property**: Required evidence that at least one Amaru output
  event reached the scored stream.
- **Fatal-consensus invariant**: A scored invariant that fails once when either
  accepted fatal signature is observed.
- **Relay log file**: A per-relay, per-testnet-run append-only regular file used
  as the primary output target and assertion-service input.
- **Output mirror**: An auxiliary, supervised reader that copies the regular
  file to container output without owning Amaru's write path.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Each of the two accepted fatal signatures produces the named
  scored failure in 100% of focused test cases.
- **SC-002**: Ordinary lines produce zero fatal-consensus failures while still
  hitting the route-liveness property.
- **SC-003**: Killing the active mirror yields a replacement within five
  seconds, with the same Amaru process identity and zero added container
  restarts.
- **SC-004**: The automated ingestion test observes a line appended after the
  watcher starts and preserves its relay identity and full contents.
- **SC-005**: The standard `cardano_amaru` compose smoke exits 0 on the final
  image and routing.
- **SC-006**: The single one-hour deployed run lists both new properties and
  records its findings comparison honestly. If the fatal property fires, the
  PR remains not-ready and the result is handed to the parent as successful
  detector evidence; if it does not, the deterministic both-way proof remains
  the evidence that the property works.
- **SC-007**: Expected combined relay-file growth over three hours remains
  approximately 4-6 MB based on measured samples; even continuously
  extrapolating the observed peak fatal burst remains below 250 MB.

## Assumptions

- Docker volumes are fresh per testnet run and have substantially more than
  250 MB available.
- Relay log output is line-oriented and the two fatal signatures remain
  stable upstream identifiers for issue #1095.
- Re-reading earlier lines after an assertion-service restart may repeat the
  first failure in the new process lifetime but cannot turn a failing run
  green.
- The image-pairing discrepancy tracked in #196 is independent of the
  ingestion logic; this ticket pins the Nix-built image containing its code.
- The repository's no-new-findings readiness gate does not distinguish a
  newly introduced regression from a newly visible pre-existing failure.
  This ticket does not weaken or except itself from that gate; the parent owns
  escalation of the final readiness decision.

## Out of Scope

- Fixing `pragma-org/amaru#1095`.
- The `cluster fork depth < k` assertion tracked by #140.
- General Docker-log collection for arbitrary services.
- Rotation or retention policy for logs beyond this testnet's run lifetime.
