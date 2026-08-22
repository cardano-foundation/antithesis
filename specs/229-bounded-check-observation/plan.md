# Plan — Issue 229 bounded bootstrap-check observation

Artifact ceiling: 5,500 bytes and 130 lines.

## Technical context

The lane starts from frozen main `9094d548`. Fire-4 created the candidate at
approximately 09:56:29Z; its bootstrap checks started reporting around
09:56:32Z, after the controller had already classified the initial empty read
as failure. PR #87 still exposes long-running bootstrap CI, so the wait must be
derived from check behavior or declared duration evidence rather than the
three-second incident interval or another unexplained constant.

Local acceptance uses the repository's direct injected Daily Amaru suite. No
Nix realization is authorized on this host; hosted exact-head checks provide
the omitted actionlint and shellcheck coverage.

## Architecture decisions

- The existing transport operation remains the sole bootstrap-check gate. It
  observes the exact candidate and emits rows only after all unchanged
  required checks are uniquely successful.
- Observation state is explicit: incomplete or initially missing rows remain
  pending before the deadline; concluded non-success is failed; absence is
  terminal only at the derived deadline.
- Check behavior/duration evidence is part of the injected transport boundary,
  so the proof can demonstrate that changing the evidence changes the bounded
  observation window. The production source may be historical or declared,
  but it must be observable, finite, candidate-relevant, and fail closed when
  unusable.
- Clock, sleeping, and GitHub responses are deterministic injected boundaries
  in tests. No fixture inherits host commands or credentials.
- Receipt schema and the caller's stage/error keys remain unchanged. The
  transport's diagnostic names the distinguishing terminal state and check.

## Slice

One bisect-safe OWNER slice, **S229-01**. Asynchronous state classification,
retry semantics, duration provenance, and exact-success ambiguity require
semantic audit and are not eligible for LIGHT.

The commit owner supplies the complete RED proof before production changes,
then lands production and permanent regressions together. The worker may
choose the smallest internal factoring that preserves the existing command
surface and models below.

## Proof strategy

- Drive the real `require-bootstrap-checks` transport operation through a
  scripted sequence of candidate-exact observations and behavior evidence.
- Require explicit evidence of more than one observation for pending→success
  and pending→failure; derive poll/deadline counts from executed effects.
- Vary the supplied duration evidence so a fixed-window implementation is
  rejected.
- Inject transient and persistent transport failures, proving the former can
  recover and the latter terminates distinctly without becoming a check
  verdict.
- Supply wrong-head, duplicate, partial, unsuccessful, and never-reported
  rows; only the exact all-success set may proceed.
- Apply and prove an immediate-read mutant, then require its output to match
  fire-4's not-yet-reported failure class.
- Retain hermetic PATH, effect census, receipt schema, and zero-launch controls.

## Verification envelope

- Frozen untracked `./gate.sh` and its runtime backup.
- Focused bounded-observation scenarios and complete
  `just test-daily-amaru`.
- Shell syntax, exact changed-path census, marker derivation, and mutation
  application checks.
- No local `nix develop -c just ci`; the omission is named in gate/PR evidence.
- Six required hosted contexts green on the exact final head.

## Stop conditions

Stop and ask before changing required checks, candidate construction, receipt
keys, cap/supersede semantics, credentials, workflows, Amaru bootstrap files,
or any real effect; before using a non-derived fixed observation window; or
before realizing Nix locally.
