# Data model: Amaru fatal-log ingestion

## Amaru stdout event

One normalized event per complete relay-output line.

| Field | Meaning | Validation |
|---|---|---|
| ingestion time | Time the sidecar read the line | Valid UTC timestamp |
| namespace | Event family | Exactly `Amaru.Stdout` |
| kind | Rule-dispatch tag | Exactly `AmaruStdout` |
| source | Original transport | Exactly `amaru-container-stdout` |
| host | Relay identity derived from the file name | `amaru-relay-1` or `amaru-relay-2` |
| message | Original line | Preserved completely, excluding line terminator |

The normalized event retains the existing generic log fields so it can pass
through the current sidecar rule engine. Its generic severity is informational;
the dedicated fatal-signature rule owns classification.

## Assertion state

The existing `unreachedAssertions` set provides one-shot state for both new
rules:

- `amaru stdout observed` starts unreached and emits its hit on the first Amaru
  stdout event.
- `no fatal amaru consensus logs` starts armed and emits its failure on the
  first matching line.

No new persistent state or external database is introduced.

## Relay log files

| File | Writer | Readers | Lifetime |
|---|---|---|---|
| `amaru-relay-1.log` | relay 1 PID 1 | mirror and tracer-sidecar | Docker volume lifetime |
| `amaru-relay-2.log` | relay 2 PID 1 | mirror and tracer-sidecar | Docker volume lifetime |

Files are append-only regular files. The mirror is never on the writer's file
descriptor path.

## State transitions

```text
no relay file
  -> file created by relay command
  -> Amaru appends line
  -> mirror copies line to container stdout
  -> tracer-sidecar normalizes line
  -> route-liveness property hits (first event only)
  -> fatal invariant either remains armed or fails (first signature only)
```

Mirror failure is an independent transition:

```text
mirror active -> mirror killed/paused -> Amaru keeps appending regular file
              -> supervisor starts replacement -> stdout mirroring resumes
```
