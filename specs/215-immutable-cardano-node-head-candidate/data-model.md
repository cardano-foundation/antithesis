# Data model

## D-01 `UpstreamObservation`

One line emitted per observed remote head by `resolve-upstream`.

| Field | Type | Validation |
|---|---|---|
| `origin` | string | must equal `https://github.com/IntersectMBO/cardano-node.git` |
| `ref` | string | must equal `refs/heads/master` |
| `sha` | string | must match `^[0-9a-f]{40}$` |

State invariant: the controller accepts exactly one non-empty observation line
with exactly three `|`-separated fields. Zero, more than one, a trailing extra
field, a differing origin, a differing ref, or a non-conforming SHA is a
fail-closed `resolve-upstream` rejection.

## D-02 `CandidateRef`

The immutable candidate image identity.

| Field | Type | Validation |
|---|---|---|
| `repository` | string | non-empty, no whitespace, no `@` or `:` |
| `tag` | string | must match `^[0-9a-f]{40}$` and equal the D-01 `sha` |
| `digest` | string | must match `^sha256:[0-9a-f]{64}$` |

Rendered form is exactly `repository:tag@digest`. No other rendering of
candidate identity may appear in a receipt, a rendered model, or a document.

## D-03 `RevisionProof`

| Field | Type | Validation |
|---|---|---|
| `revision` | string | must match `^[0-9a-f]{40}$` and equal the D-01 `sha` |

State invariant: observed from the running container's own `cardano-node`
binary. Build metadata, image labels, and tag names are not admissible sources.

## D-04 `TopologyRow`

One line per Compose-resolved service emitted by `describe-topology`.

| Field | Type | Validation |
|---|---|---|
| `service` | string | non-empty, no `|` |
| `image` | string | non-empty, no whitespace |

State invariants over the row set:

- the set of services whose name matches `^(p[1-4]|relay[1-3])$` must equal
  exactly `{p1,p2,p3,p4,relay1,relay2,relay3}`;
- every such row's `image` must equal the D-02 rendered form byte-for-byte;
- no row of any service may reference `ghcr.io/intersectmbo/cardano-node` with a
  value other than the candidate;
- an empty row set is a rejection, never a vacuous pass.

## D-05 `CandidateReceiptV1`

Append-only key=value records, one line per field, written once per stage.

| Field | Present when | Validation |
|---|---|---|
| `schema` | always | literal `CandidateReceiptV1` |
| `stage` | always | one of the stage names in `plan.md` |
| `outcome` | always | `OBSERVED`, `PUBLISHED`, `PROVEN`, `RENDERED`, `VERIFIED`, `VALIDATED`, `PREPARED`, or `FAILED` |
| `error` | `outcome=FAILED` only | non-empty stable reason token; cleared on every non-failing record |
| `mode` | always | the controller mode |
| `upstream_origin`, `upstream_ref` | always | D-01 constants |
| `upstream_sha` | from `resolve-upstream` on | D-01 `sha` |
| `candidate_ref` | from `publish-candidate` on | D-02 rendered form |
| `binary_revision` | from `prove-revision` on | D-03 `revision` |
| `rendered_model` | from `render-topology` on | absolute path inside the state directory |
| `topology_services`, `topology_image` | from `verify-topology` on | census count and the one distinct image |
| `submission` | from `submit-candidate` on | must begin with `fake://` |

State invariants: a record whose `outcome` is not `FAILED` never carries
`error`; a `FAILED` record never carries a later stage's fields; no field value
may be a credential or contain one.

## D-06 `ControllerMode`

Enumeration: `test`, `manual`. `test` selects the fake transport by injection;
`manual` uses the real transport with the fake submission operation. No value
in #215 enables a real submission; an unrecognized mode is a fail-closed
rejection before any effect.
