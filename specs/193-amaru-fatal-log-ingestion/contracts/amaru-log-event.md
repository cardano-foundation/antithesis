# Contract: normalized Amaru stdout event and assertions

## Accepted files

The Amaru log directory contains only per-relay files named:

- `amaru-relay-1.log`
- `amaru-relay-2.log`

Other entries are ignored. Each complete line becomes one event; the newline is
not part of `message`.

## Normalized evidence object

The SDK failure's `details` value must preserve this logical shape:

```json
{
  "source": "amaru-container-stdout",
  "host": "amaru-relay-1",
  "message": "ERROR amaru::cmd::node::run: Consensus died, ..."
}
```

Additional generic event fields may be present, but these three fields and their
contents are normative.

## Property identifiers

### `amaru stdout observed`

- Type: Sometimes
- Required: yes
- Declared only when Amaru ingestion is configured
- Hit: first normalized Amaru stdout event

### `no fatal amaru consensus logs`

- Type: AlwaysOrUnreachable
- Declared only when Amaru ingestion is configured
- Fails on a case-sensitive substring match for either:
  - `Consensus died`
  - `attempted roll back in the future`
- Failure details: the normalized evidence object above
- Ordinary lines: no failure output

## Configuration contract

- Absence of the Amaru log-directory configuration means neither Amaru-specific
  property is declared.
- Presence means both properties are declared and the directory watcher starts.
- Existing cardano-tracer event processing remains unchanged.
