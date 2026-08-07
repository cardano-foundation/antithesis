# Daily Amaru walking skeleton

The daily controller is a deliberately thin, supervised path from bare
`pragma-org/amaru` `refs/heads/main` to one exact `cardano_amaru` test request.
It runs on one fixed UTC cron. Pull requests and manual dispatches execute the
same state machine through the deterministic fake transport and cannot call
the real launcher.

## Scheduled runner contract

The scheduled job provisions every non-shell command the production controller
and transport can reach — `ripgrep` from the runner package index and `nix` from
the shared setup action — on top of what the stock image already carries. Before
the UTC day is claimed, the controller asks the transport to preflight that
census. A missing command is a controller precondition failure, never a setup
exception: the run exits non-zero at `stage=runner-preflight` with
`error=missing-command-<name>`, and a preflight that reports nothing or reports
an unparsable success is rejected as `error=malformed-dependency-evidence`.

Each transport operation declares only the commands it uses, so publishing a
failure receipt never depends on the command whose absence it reports.

## Bootstrap App identity

Production mints a short-lived token at runtime from a dedicated GitHub App,
read from repository variable `DAILY_AMARU_APP_ID` and Actions secret
`DAILY_AMARU_APP_PRIVATE_KEY`. The token is scoped to owner `lambdasistemi`,
repository `amaru-bootstrap` alone, and exactly five permissions: actions read,
checks read, contents write, pull requests write, and metadata read.

That token authorizes the bootstrap boundary only. Same-repository work — the
receipt issue, the consumer repin, consumer check observation, and the launch —
uses the workflow's own short-lived repository token, which is a separate value
and is never a substitute for the minted one.

The private key and the minted token are never printed, written to a receipt or
state artifact, exported through `$GITHUB_ENV`, committed, or reused outside the
single controller step. The token reaches the transport as a step-scoped
environment binding, never as a command-line argument.

If the variable, the secret, or the mint step is unavailable, the mint step is
allowed to fail and the controller still runs with an empty bootstrap identity.
It then exits non-zero at `stage=identity` with
`error=missing-production-identity` before any bootstrap proposal, image
resolution, consumer repin, integration, or launch.

## Durable failure receipts

Every receipt is written to the local receipt file before external publication
is requested, and the scheduled job uploads that file as an artifact on every
outcome, including failure. A broken precondition therefore leaves the UTC day,
the precise stage, `outcome=FAILED`, and a stable specific error behind even
when the GitHub transport cannot publish its ordinary issue receipt.

## Operator setup gate

This repository implements the interface and the loud missing-input behavior
only. Creating the App, installing it on `lambdasistemi/amaru-bootstrap`,
approving its permissions, and placing `DAILY_AMARU_APP_ID` and
`DAILY_AMARU_APP_PRIVATE_KEY` remain operator actions performed outside this
repository. Until they are done, the scheduled run is expected to fail at
`stage=identity`; that is the contract working, not a regression. No secret
value is recorded here or anywhere in the repository.

## Decision and durable guards

The GitHub transport first claims the UTC day in issue #210, resolves exactly
one 40-character SHA from the bare upstream ref, and compares it with the last
successful SHA in the receipt stream. An equal SHA records `UNCHANGED` without
mutation or launch. A changed SHA must claim a no-retry attempt marker before
any cross-repository mutation. Duplicate days, attempted SHAs, malformed or
ambiguous observations, and every failed stage retain an honest `FAILED`
receipt.

## Supervised changed path

The provisional transport:

1. proposes only the stock Amaru lock update in
   `lambdasistemi/amaru-bootstrap`;
2. waits for named checks on that exact candidate and resolves its full SHA
   image tag to a lowercase registry digest;
3. atomically repins every discovered `cardano_amaru` producer reference;
4. requires the named workflow/job results on the exact consumer head and
   retains the positive, non-zero output from
   `scripts/check-amaru-producer-image-refs.sh`;
5. waits for lane-supervised guarded integration and verifies the merge is
   exact current `main`—the transport has no generated-PR self-merge command;
6. invokes `cardano-node.yaml` once with `test=cardano_amaru`, `duration=1`,
   and `no-faults=false`, then waits for the run result before recording the
   upstream SHA as successful.

There is no automatic retry. A failed partial receipt stays failed; it is not
translated to `UNCHANGED`, launch success, or a findings verdict.

## Replacement owners

The production source marks each provisional mechanism once with its owner:
`amaru-bootstrap#75` replaces the crude stock-pin handoff,
`cardano-node-antithesis#208` supplies complete exact-revision preflight,
`cardano-node-antithesis#207` supplies guarded unattended integration and
correlation, and `cardano-node-antithesis#206` supplies complete property
receipts and a missing-day alarm.

## Local proof

Run the deterministic controller suite without credentials or network access:

```console
tests/test-daily-amaru.sh
```

It exercises changed, unchanged, malformed observations, exact-head check
failures, non-vacuous #202 evidence, duplicate/no-retry guards, failure
ordering, receipt honesty, and the counted zero-real-launch invariant.

It also reproduces the 2026-08-02 and 2026-08-03 missing-`rg` incidents against
the real transport in a hermetic seeded PATH, checks the dedicated App scope and
credential non-persistence, counts the business effects both broken
preconditions reach, and checks that pull-request CI runs this suite while the
schedule runs the same controller contract. Every instrument in it — the receipt
oracle, the seeded PATH, the dependency preflight, the identity boundary, and
the secret scan — carries controls proving it can fail.
