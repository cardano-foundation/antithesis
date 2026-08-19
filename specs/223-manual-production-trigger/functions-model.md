# Functions model — Issue 223

Artifact ceiling: 3,500 bytes and 70 lines.

Only new or changed signatures. Local helpers are the implementer's choice.

## `scripts/daily-amaru-github.sh` — transport operations

| Operation | Arguments | Result |
|---|---|---|
| `claim-day` | `day` (`YYYY-MM-DD`), `head` (sha40) | claim verdict on stdout; exit 0 claimed/superseded, non-zero blocked |
| `claim-sha-attempt` | `sha` (sha40), `head` (sha40) | claim verdict; same vocabulary |
| `claim-launch` | `day` (`YYYY-MM-DD`), `head` (sha40) | `CLAIMED` on stdout, exit 0; `BLOCKED <reason>` and non-zero otherwise |

`claim-day` and `claim-sha-attempt` change arity: both gain the required
trailing `head`. A call missing it is a hard error, never a silent legacy path.

Internal, transport-private:

| Function | Arguments | Result |
|---|---|---|
| `marker_census` | none | every issue-comment body on stdout; non-zero when the census could not be read, with no partial body treated as complete |

## `scripts/daily-amaru.sh` — controller

| Function | Arguments | Result |
|---|---|---|
| `workflow_head` | none | the current head string; builtin-only, no external command |

Changed call sites, in existing stage order:

| Stage | Change |
|---|---|
| `head-resolution` (new, before `day-claim`) | derives, validates, and exports the head; refuses the run on an unresolvable or malformed head |
| `day-claim` | passes `head`; maps `BLOCKED <reason>` to `fail_stage day-claim <reason>` and records `claim_supersedes` on a supersede |
| `launch-attempt` | passes `head`; same verdict mapping under `fail_stage launch-attempt <reason>` |
| `launch-cap` (new, after `supervised-integration`, before the launcher, production mode only) | calls `claim-launch`; on refusal `fail_stage launch-cap <reason>` with zero launcher invocations |

`transport_call`'s signature is unchanged. No existing stage name, receipt key,
exit code, or marker is renamed or removed.

## `tests/fixtures/daily-amaru/fake-transport.sh`

Implements `claim-day`, `claim-sha-attempt`, and `claim-launch` with the exact
arity above, logging the head it observed so the propagation census can read
it. Its claim-operation set is reconciled mechanically against the production
transport.
