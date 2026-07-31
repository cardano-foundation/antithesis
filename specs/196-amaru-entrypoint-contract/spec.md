# Issue 196 — Enforce the Amaru sidecar entrypoint contract

## Priority story

As an operator preparing `cardano_amaru`, I need a reusable check that starts
the exact tracer-sidecar image through the rendered Compose service and proves
the resulting executable and arguments, so a tag, image build, or Compose
override cannot leave model validation green while container startup is
broken.

## Current and historical boundary

The accepted base is already green because `tracer-sidecar:a94197a` has image
`Entrypoint=["tracer-sidecar"]`, and Compose replaces its empty image `Cmd`
with `["/opt/cardano-tracer/logs"]`. The missing behavior is permanent,
non-vacuous reconciliation at the actual container boundary.

The historical local-versus-Antithesis discrepancy was an image identity
discrepancy, not different command semantics:

- the failed fresh-local probe observed a Dockerfile-shaped `e01ad90` image
  with no entrypoint and
  `Cmd=["/usr/local/tracer-sidecar","/opt/cardano-tracer/logs"]`;
- completed Antithesis run
  `5271f5ea22ddde7a6f674084905aa335-56-17` used consumer commit `95306662`
  and tracer-sidecar manifest digest
  `sha256:9c7fc575e32c0ca2789fa507632a7ba040b160c2bdeb4251f872e26390e3192a`;
- that exact registry manifest has `Entrypoint=["tracer-sidecar"]` and no
  `Cmd`, the run logged `starting tracer-sidecar...`, and it emitted two
  `cluster fork depth < k` counterexamples from
  `tracer-sidecar.example`.

The mutable `e01ad90` tag therefore named differently built/cached local and
registry artifacts. Exact digest evidence is part of the new passing signal so
this ambiguity cannot recur silently.

## Functional requirements

- FR-001: Ship one repository-conventional executable check for a selected
  service in one or more Compose files.
- FR-002: The check accepts repeated Compose `-f` inputs, a required service,
  an externally supplied expected argv JSON array, and an optional exact image
  override for downstream preflight use.
- FR-003: An image override is accepted only in digest-pinned
  `repository@sha256:<64 lowercase hex>` form. Without an override, the check
  pulls the image rendered by Compose and records the digest actually pulled.
- FR-004: Service discovery is performed against rendered Compose JSON. Zero
  discovered targets fails loudly; a missing service cannot become a green
  no-op.
- FR-005: The check reports the rendered Compose `entrypoint`, `command`, and
  declared image plus the pulled image's `Entrypoint`, `Cmd`, image ID, and
  registry digest.
- FR-006: The check creates and starts an isolated, no-dependency container
  through Docker Compose, inspects the actual runtime `Path` and `Args`, and
  requires their exact concatenation to equal the supplied expected argv.
- FR-007: Success requires the container to remain running after startup. An
  OCI-start failure, immediate exit, wrong executable, or wrong argument is a
  non-zero result with a mismatch diagnostic.
- FR-008: Cleanup removes only resources created by the check's unique project
  and container identity, on both success and failure.
- FR-009: Success writes exactly one canonical JSON object to stdout and human
  diagnostics to stderr. The object has the stable fields `schema`,
  `target_count`, `service`, `declared_image`, `checked_image`,
  `resolved_digest`, `image_id`, `image_entrypoint`, `image_cmd`,
  `compose_entrypoint`, `compose_command`, `runtime_argv`, and `state`.
  `schema` is `compose-image-entrypoint/v1`, `target_count` is non-zero, and
  every identity and metadata value is observed rather than inferred.
- FR-010: `scripts/smoke-test.sh cardano_amaru ...` invokes the focused check
  before starting the full stack. This is the shared local/hosted reachability
  point used by the standalone and publish-images smoke workflows.
- FR-011: A temporary Compose entrypoint mismatch makes the focused check and
  the wired smoke gate fail before full deployment. Restoring the exact bytes
  makes both green.
- FR-012: Documentation records the historical image-identity answer and the
  released command, input contract, output contract, and downstream release
  signal.

## Rejection behavior

The check must fail for malformed CLI input, unreadable or invalid Compose,
zero service matches, a non-digest image override, pull/inspect/create/start
errors, missing digest evidence, runtime argv disagreement, an exited
container, or incomplete owned-resource cleanup. Failure output identifies the
selected service and the observed mismatch when those facts are available.

## Observable success

- The direct command exits zero and its sole stdout line parses as the approved
  `compose-image-entrypoint/v1` object for exactly one `tracer-sidecar` target,
  its exact registry digest, the image and Compose command fields, runtime
  argv `["tracer-sidecar","/opt/cardano-tracer/logs"]`, and `state=running`.
- A known-missing service proves the discovery method can observe absence by
  exiting non-zero with `target_count=0`.
- A seeded empty entrypoint makes Docker attempt the log directory as the
  executable and turns the focused and wired checks red.
- The original Compose bytes are hash-identical after restoration and the same
  direct and wired gates return green.
- Pull-request CI reaches the check through the existing hosted
  `cardano_amaru` smoke path and retains its non-vacuous success output.

## Scope boundaries

- Do not change tracer-sidecar property semantics, Haskell scoring, Amaru
  producer images, daily scheduling, MOOG behavior, report generation, or
  issue #140.
- Do not launch an Antithesis run.
- Do not change the meaning of existing Amaru producer-image references.
- Keep all runtime evidence, seeded files, and the ticket gate outside Git.
