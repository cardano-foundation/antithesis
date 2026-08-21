# Functions model — Issue 227

Artifact ceiling: 2,500 bytes and 65 lines.

No new public command is introduced.

## F227-1 — `classify_proposal_branch`

- Arguments: `directory: path`, `branch: string`, `upstream_sha: 40-hex`,
  `input_node: lock-node-name`.
- Result: one line, `absent | adoptable | foreign`; non-zero on unreadable Git
  state.
- Effects: read-only Git and artifact inspection.
- Changed constraint: `adoptable` entails D227-1 and D227-2, not a lock-only
  delta.

## F227-2 — transport operation `propose-bootstrap`

- Argument: `upstream_sha: 40-hex`.
- Environment: existing day, state-root, repository and identity fields.
- Result: exact 40-hex candidate SHA on success; non-zero with a typed
  resolver-failure observation on D227-4 failures.
- Effects: clone workspace; bootstrap-owned input updates and resolver call;
  one local commit; proposal push and PR creation only after validation.
- Changed constraint: success entails D227-1 and D227-2.

## F227-3 — `transport_call`

- Existing variadic transport invocation; signature unchanged.
- Changed result constraint only for the bootstrap proposal: resolver-specific
  failure remains distinguishable so M227-3 can write D227-4.
