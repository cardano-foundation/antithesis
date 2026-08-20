# Data model

## D-225-1 Transport output streams

| Stream | Carries | Consumer |
|---|---|---|
| value channel | exactly the operation's value, nothing else | the controller's `$(...)` capture |
| diagnostic stream | every subcommand's stdout and stderr, and the transport's own diagnostics | the run log |

Invariant: no subcommand may reach the value channel. The reservation happens
once, at the transport's dispatch boundary, before any operation runs.

## D-225-2 Operation value census

Complete classification of `scripts/daily-amaru-github.sh` at base `01f96e4`.
The exact value shapes are the contract the controller already validates.

| Operation | Value | Controller validation | Class-A status at base |
|---|---|---|---|
| `preflight` | `OK: <n> scheduled dependencies present: <list>` or `MISSING-COMMAND <name>` | regex | clean |
| `claim-day` | `CLAIMED` \| `SUPERSEDED previous-head=<sha>` \| `BLOCKED <reason>` | exact match | clean |
| `claim-sha-attempt` | as `claim-day` | exact match | clean |
| `claim-launch` | as `claim-day` | exact match | clean |
| `resolve-upstream` | one `origin\|ref\|sha` line | field split + regex | clean |
| `last-success-sha` | 40-hex SHA or empty | regex | clean |
| `propose-bootstrap` | 40-hex SHA | regex | **POLLUTED — fired**: `git commit` summary |
| `require-bootstrap-checks` | check rows | not consumed | clean |
| `resolve-image` | `<image>:<sha>@sha256:<digest>` | regex | clean |
| `prepare-consumer-repin` | 40-hex SHA | regex | **POLLUTED — unfired**: `git commit` summary |
| `require-consumer-checks` | check rows | per-row field split | clean |
| `run-producer-check` | `OK: <n> producer-image reference(s), all pinned to <ref>` | whole-string regex | fragile: the checker's whole stdout is the value |
| `await-supervised-integration` | 40-hex SHA | regex | clean |
| `fake-launch` | `fake://...` | none | clean |
| `real-launch` | `https://github.com/<repo>/actions/runs/<id>` | **none** | **POLLUTED — unfired**: `gh workflow run` confirmation and `gh run watch` progress, stored raw into the receipt |
| `receipt` | no value | n/a | n/a |

`real-launch` is the most dangerous unfired instance precisely because the
controller does not validate it: pollution there corrupts the #210 receipt
rather than failing loudly.

## D-225-3 Proposal branch state

Branch name: `daily-amaru/bootstrap-<day>-<upstream-sha[0:12]>` (unchanged).

| State | Condition | Outcome |
|---|---|---|
| `absent` | no such ref on the bootstrap remote | create, commit, push, open PR |
| `adoptable` | ref exists; its delta from its merge base with `origin/main` changes exactly `flake.lock`; that lock's single stock `pragma-org/amaru` node has `locked.rev == <upstream-sha>` and `original.owner/repo == pragma-org/amaru` | emit that ref's head; no commit, no push; find the existing PR |
| `foreign` | ref exists and is not `adoptable` | named red `foreign-proposal-branch`; no value; remote untouched |

`adoptable` requires **both** conditions. A branch touching only `flake.lock`
but pinning a different revision is `foreign`, not `adoptable`.

## D-225-4 Named reds

| Token | Meaning |
|---|---|
| `foreign-proposal-branch` | the per-SHA proposal branch exists with content this controller did not produce |

The token is stable and asserted by the regression. The receipt schema is
unchanged: the controller keeps recording `error=proposal-failed` for this
stage, and the token is the diagnostic-stream evidence.
