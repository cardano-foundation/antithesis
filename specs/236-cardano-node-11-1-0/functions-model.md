# Functions model — Issue 236

Artifact ceiling: 2,000 bytes and 55 lines.

No production function or public command changes.

## F236-1 — focused release-matrix proof command

- Arguments: none; repository root is the current working directory.
- Inputs: tracked master Compose definition and the frozen release identities.
- Result: zero only when D236-1, D236-2, D236-3, and the owned portion of
  D236-4 are observable; non-zero with a named invariant on mismatch.
- Effects: temporary local files only; no registry credentials, publication,
  Compose startup, or Antithesis launch.
- Constraint: inspect the rendered Compose model, not source text alone.

## F236-2 — live 11.1.0 image probe

- Arguments: repository, release tag, expected manifest digest, platform.
- Result: zero only when anonymous resolution equals D236-2, the platform is
  present, and a bounded image invocation accepts the existing node executable
  boundary; non-zero otherwise.
- Effects: anonymous registry reads and local image cache only.
- Constraint: no credential access, tag mutation, image publication, or
  long-running node/testnet startup.

