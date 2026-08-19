# Data model — Issue 223

Artifact ceiling: 4,000 bytes and 90 lines.

## Marker vocabulary on issue #210 (append-only)

Every marker is one exact line inside an issue comment. Nothing is ever
deleted or rewritten; a later marker supersedes an earlier one by existing.

| Marker | Form | State it records |
|---|---|---|
| day claim (legacy) | `<!-- daily-amaru day=<day> claim -->` | day claimed, claiming head unknown |
| day claim | `<!-- daily-amaru day=<day> claim head=<sha40> -->` | day claimed by that workflow head |
| launch claim | `<!-- daily-amaru day=<day> launch-consumed head=<sha40> -->` | the day's one real launch is spent |
| attempted SHA (legacy) | `<!-- daily-amaru attempted-sha=<sha40> -->` | upstream SHA attempted, claiming head unknown |
| attempted SHA | `<!-- daily-amaru attempted-sha=<sha40> head=<sha40> -->` | attempted by that workflow head |
| last success | `<!-- daily-amaru last-success sha=<sha40> -->` | unchanged |
| receipt | `<!-- daily-amaru receipt -->` + `- key=value` | unchanged |

`<day>` is `YYYY-MM-DD`; `<sha40>` is exactly 40 lowercase hex characters.
Legacy forms are recognised forever: they are the durable record of every run
before this change, including the 2026-08-19 claim this ticket unblocks.

## Claim verdict

Produced by the transport, consumed by the controller. The controller never
parses a marker.

| Verdict | Stdout | Exit | Meaning |
|---|---|---|---|
| claimed | `CLAIMED` | 0 | no prior marker; a new one was appended |
| superseded | `SUPERSEDED previous-head=<sha40\|legacy>` | 0 | prior pre-launch claim, head differs; a superseding marker was appended |
| blocked | `BLOCKED <reason>` | non-zero | refused, nothing appended |

Blocked reasons, each a distinct named receipt error:

- `launch-consumed` — the day already holds a launch claim (final, whatever the head)
- `unchanged-head` — a prior pre-launch claim recorded this exact head
- `census-unreadable` — the marker census could not be read

## Head state

| Value | Source | Rule |
|---|---|---|
| current head | `DAILY_AMARU_HEAD`, else `GITHUB_SHA` | must match `^[0-9a-f]{40}$`; unresolvable or malformed refuses the run at stage `head-resolution` before any claim |
| recorded head | the marker's `head=` field | absent (legacy) counts as *differs from current* |

## Receipt fields added

Appended to `receipt_keys` after the existing `day` group; every existing key,
value, and order is unchanged.

| Key | Value | Written at |
|---|---|---|
| `workflow_head` | current head, 40 hex | first receipt of the run |
| `claim_supersedes` | previous head or `legacy` | day-claim stage, only on a supersede |
| `launch_claim` | `consumed` | launch-cap stage, before the launcher |

## State invariants

- For one `<day>`, at most one launch claim is ever admitted.
- A day holding a launch claim admits no further claim that day.
- A day holding only pre-launch claims admits a new claim iff the current head
  differs from every recorded head on those claims.
- A refused claim appends nothing.
- Marker count over issue #210 is monotonically non-decreasing.
