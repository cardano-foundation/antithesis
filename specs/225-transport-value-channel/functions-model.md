# Functions model

New and changed signatures only. No bodies, no algorithms.

## `scripts/daily-amaru-github.sh`

| Function | Arguments | Result | Constraints and effects |
|---|---|---|---|
| `emit` | `line...` (one or more value lines) | none | Writes its arguments, and nothing else, to the reserved value channel (`D-225-1`). The only way any operation may produce a value. Never writes to the diagnostic stream. |
| `classify_proposal_branch` | `directory` (local clone), `branch`, `upstream_sha`, `input_node` (lock node key) | prints one of `absent`, `adoptable`, `foreign` on its own stdout, captured by the caller | Pure read: performs no commit, no push, no working-tree mutation, and no PR call. Must be evaluated before the local branch is created. Non-zero exit only for an unreadable remote, which is distinct from `foreign`. |

Changed callers: every `case` branch that today ends in a bare `printf` of its
value now ends in `emit`. `push_branch` and `create_or_find_pr` keep their
current signatures; `propose-bootstrap` simply does not call `push_branch` in
the `adoptable` path.

The owner may add further private helpers. Those two signatures are the
contract, because each carries an invariant: `emit` is the sole value path, and
`classify_proposal_branch` is a mutation-free pre-check.

## `scripts/daily-amaru.sh`

No new or changed signatures. `receipt_keys`, stage names, and every validation
regex are frozen.

## `tests/fixtures/daily-amaru/`

| Fixture | Invocation surface | Constraints |
|---|---|---|
| `gh` stand-in (existing file, extended) | `repo clone <repo> <dir> -- <git-args...>`, `pr create -R <repo> --base <b> --head <h> --title <t> --body <b>`, `pr view <ref> -R <repo> --json <fields> [--jq <expr>]`, plus the existing `api` and `issue comment` surface | `repo clone` delegates to real `git clone` against a `file://` remote. Must reject a subcommand or flag the real `gh` would reject, so the double cannot drift more permissive than the binary it stands for. Every invocation stays recorded in the existing effect log. |
| lock rewriter (new, stands in for `nix`) | `flake lock --override-input <input-name> github:pragma-org/amaru/<sha>` | Rewrites `flake.lock` for that node exactly as the real command does for the fields the transport validates (`original.owner`, `original.repo`, `locked.rev`), deterministically and offline. Writes its progress to the same stream the real `nix` writes it to. Rejects any other argument shape. |

`git` is the real binary in every new proof and may not be stubbed: its stdout
behaviour is the defect under test.
