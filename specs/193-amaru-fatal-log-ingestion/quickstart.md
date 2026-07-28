# Quickstart: verify Amaru fatal-log ingestion

All evidence commands use `set -o pipefail`, capture stdout and stderr to raw
files, record real exit codes and UTC timestamps, and hash artifacts only after
the producing command has completed.

## Focused tests

From `components/tracer-sidecar`:

```bash
nix develop -c just test "amaru stdout"
nix develop -c just test "fatal amaru"
```

Required signals:

- the route-liveness property is declared and hit for an ordinary line;
- `Consensus died` emits the fatal invariant failure;
- `attempted roll back in the future` emits the same failure;
- an ordinary line emits no fatal invariant failure;
- a line appended to a watched relay file is normalized with host and message.

## Mechanical gate

From the repository root:

```bash
./gate.sh
```

## Compose contract

```bash
INTERNAL_NETWORK=false docker compose \
  -f testnets/cardano_amaru/docker-compose.yaml config >/dev/null
```

Verify the `amaru-consumer-seed` image line is byte-identical to the base.

## Mirror fault proof

On an isolated fresh project:

1. Confirm PID 1 is `/bin/amaru node run`, stdout points to a regular file, and
   restart count is zero.
2. Read the active mirror PID and terminate only that process.
3. Within five seconds, confirm a different mirror PID is alive.
4. Confirm the container is still running, the Amaru host PID is unchanged,
   restart count is still zero, and stdout still points to the regular file.
5. Append a controlled marker to the shared file and confirm it appears in
   Docker logs.

## Live ingestion proof

With the final image and compose route:

1. Confirm an ordinary relay line exists in the shared file and the route
   property is hit in `sdk.jsonl`.
2. Append a controlled fatal fixture to a relay file through the mounted
   boundary.
3. Copy `sdk.jsonl` out of tracer-sidecar and confirm
   `no fatal amaru consensus logs` has `hit=true` with source, host, and the
   original line.
4. Recreate the project without the fatal fixture and confirm the route property
   hits while the fatal invariant emits no failure.

## Deployment gates

- `publish-images` green for the code-commit image.
- `Compose smoke test` green for `cardano_amaru`.
- Exactly one one-hour Antithesis run lists both properties and records
  `findings_new` against the accepted baseline. Do not retry to select a clean
  schedule. A naturally observed fatal-property failure is successful detector
  evidence and leaves the PR not-ready for the parent-owned governance call;
  a clean schedule does not replace the deterministic both-way proof.
