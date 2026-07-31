# Plan — Issue 196

## Technical context

The clean accepted base `d7e4416713a6c3a006dc121506afd128e7224cee`
passes all four required baseline commands. The model and unit layers are
green, and the full smoke confirms the current `a94197a` Nix image starts with
the intended executable and argument. Evidence is retained under the ticket
runtime root in `evidence/baseline/`.

Read-only Antithesis API evidence in `evidence/historical/` settles the old
discrepancy: run `5271f5ea22ddde7a6f674084905aa335-56-17` resolved the
`e01ad90` tag to manifest digest `sha256:9c7fc575...`, whose entrypoint is
`tracer-sidecar`. The broken local probe had the Dockerfile-shaped image under
the same mutable tag. The durable control must therefore pull or accept an
exact digest and print it.

The previous tracked project `gate.sh` has been migrated in setup commit
`a6a6559` to the current ignored ticket-local lifecycle. Its exact baseline
bytes are backed up at the runtime root and will be extended locally; no gate
file enters the PR.

## Released command proposal

Subject to the parent ruling for the shared #208 contract, the command is:

```sh
./scripts/check-compose-image-entrypoint.sh \
  -f testnets/cardano_amaru/docker-compose.yaml \
  --service tracer-sidecar \
  --expected-argv '["tracer-sidecar","/opt/cardano-tracer/logs"]' \
  [--image repository@sha256:<digest>]
```

Repeated `-f` inputs support controlled Compose overlays. Omitting `--image`
checks the freshly pulled rendered image; #208 supplies `--image` to bind its
exact pre-launch digest set. Exit zero is the release signal. Success writes
exactly one canonical JSON object to stdout; human progress and diagnostics go
to stderr. The stable object shape is:

```json
{"schema":"compose-image-entrypoint/v1","target_count":1,"service":"tracer-sidecar","declared_image":"<compose image>","checked_image":"<declared or exact override>","resolved_digest":"<repository>@sha256:<digest>","image_id":"sha256:<id>","image_entrypoint":["tracer-sidecar"],"image_cmd":null,"compose_entrypoint":null,"compose_command":["/opt/cardano-tracer/logs"],"runtime_argv":["tracer-sidecar","/opt/cardano-tracer/logs"],"state":"running"}
```

#208 treats any non-zero exit as a launch-blocking interface alarm. Changing
the command surface, field set, or field meaning requires a new parent ruling.

## Pre-falsification

Before implementation the ticket owner freezes one runtime slice gate and
records its hash. The unchanged base is RED because the released command and
its smoke reachability do not exist. Independently, a temporary Compose
overlay clears the current image entrypoint and demonstrates the real Docker
failure mode: the log directory becomes the executable and container startup
returns non-zero. This proves the criterion at the boundary rather than only
proving a future parser can reject a fixture.

The immutable slice gate later exercises:

1. shell syntax and ShellCheck for changed shell files;
2. zero-target discovery rejection;
3. the exact current direct live-boundary command;
4. a seeded entrypoint mismatch through a temporary overlay;
5. source-level reachability from the `cardano_amaru` smoke path;
6. the runtime snapshot of the ticket-local full gate.

The ticket gate retains the required Compose config, producer-image census,
tracer-sidecar tests, direct entrypoint check, and full 700-second Amaru smoke,
ordered from cheap to expensive.

## Slice 1 — Implement, wire, and document the live contract

Topology is `PAIR` because correct behavior spans registry identity, Compose
rendering, Docker runtime semantics, resource cleanup, and a historical
explanation. The driver is Qwen `qwen3.8-max-preview`; the navigator is Codex
`gpt-5.6-sol` at xhigh effort. Claude is forbidden by the provider hold.
Nested driver tools are forbidden: the slice is compact and semantically
relational, with no eligible low-semantic-density production unit.

Owned implementation files:

- `scripts/check-compose-image-entrypoint.sh`
- `scripts/smoke-test.sh`
- `testnets/cardano_amaru/README.md`

The current `testnets/cardano_amaru/docker-compose.yaml` is an allowed evidence
surface but needs no permanent change unless the pair proves otherwise and
files a question. No workflow edit is planned because both hosted smoke paths
already invoke `scripts/smoke-test.sh cardano_amaru`; wiring the preflight in
that shared command is the minimum local/hosted seam.

Commit subject:

`fix(cardano_amaru): enforce image entrypoint contract`

Commit trailer:

`Tasks: T1961, T1962, T1963, T1964`

## Pair proof contract

The driver first posts a concrete cleanup-safe plan. The navigator's
PROVE-LIST must cover CLI rejection, positive target discovery, digest
resolution, exact argv comparison, actual successful start, mismatch startup
failure, isolated cleanup, smoke reachability, and historical accuracy.

RED is the frozen gate's missing-check/reachability failure plus the independent
live mismatch control. GREEN requires the direct check and wired ticket gate,
with evidence mechanically captured after the final edit. Neither worker may
push or alter the gate/spec/tasks/PR metadata.

## Ticket-owner acceptance

After matching driver and navigator commit events, the ticket owner will:

1. inspect the complete diff and exact owned-file fence;
2. rerun the frozen slice gate, direct command, ticket gate, and required
   baseline commands;
3. temporarily seed the tracked Compose service with an entrypoint mismatch,
   require the wired gate to fail with the named mismatch, restore via the
   inverse patch, and prove the original SHA-256 hash and byte comparison;
4. rerun direct and wired GREEN from the restored tree;
5. stamp only `tasks.md` into the still-local behavior commit and rerun the
   commit gate and proof;
6. push, refresh the PR body, verify the current-head hosted check contains the
   `compose-image-entrypoint/v1` success evidence, and mark ready only when all
   required CI is green.
