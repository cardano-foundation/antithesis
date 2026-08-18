#!/usr/bin/env bash
# Focused proof for issue #219.
#
# GitHub evaluates a workflow's job-level mappings before it allocates a runner.
# A `runner` lookup there is rejected outright and the workflow creates zero
# jobs, so every other required context can be green while nothing ran. This
# proof owns three things: the repaired allocation boundary, a repository-wide
# expression-context census that cannot pass vacuously, and the fact that a
# merge-required context still calls that census.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

command_path=scripts/check-github-actions.sh
daily_amaru=.github/workflows/daily-amaru.yaml
quality_workflow=.github/workflows/tracer-sidecar-CI.yaml
actionlint_config=.github/actionlint.yaml
justfile_path=justfile
validator_command='nix develop --quiet -c just check-workflows'

fail() {
  printf 'FAIL %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS %s\n' "$1"
}

tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT
mutant_root="$tmp_root/mutants"
mkdir -p "$mutant_root"

# Every mutant verifies its own application. A silently unapplied edit would
# otherwise report "the check caught it" while nothing was ever mutated.
# A leading `!` means the mutation is proved by the absence of a line.
reject_mutant() {
  local label=$1 source=$2 script=$3 applied=$4 why=$5
  shift 5
  local mutant="$mutant_root/$label"
  sed "$script" "$source" >"$mutant"
  if [ "${applied:0:1}" = '!' ]; then
    ! grep -Fqx -- "${applied:1}" "$mutant" || fail "mutation did not apply: $label"
  else
    grep -Fqx -- "$applied" "$mutant" || fail "mutation did not apply: $label"
  fi
  if "$@" "$mutant"; then
    fail "check accepted $why"
  fi
}

# A named step's own lines, so a binding belonging to a neighbouring step can
# never be read as this one's.
workflow_step() {
  awk -v header="      - name: $2" '
    $0 == header { inside = 1 }
    inside && $0 != header && /^      - (name|uses):/ { exit }
    inside { print }
  ' "$1"
}

# ---------------------------------------------------------------------------
# INV-219-01 — runner-scoped paths are bound only after allocation.
#
# Job-level mapping entries sit at exactly six columns; step-level ones sit at
# ten. Matching the column is what separates the incident from the legitimate
# step-scoped lookups the same workflow still makes.
# ---------------------------------------------------------------------------

job_level_runner_refs() {
  grep -cE '^ {6}[A-Za-z_][A-Za-z0-9_-]*:.*\$\{\{[^}]*runner\.' "$1" || true
}

allocation_boundary_holds() {
  local step
  [ "$(job_level_runner_refs "$1")" -eq 0 ] || return 1
  step=$(workflow_step "$1" 'Run the once-daily state machine')
  # shellcheck disable=SC2016
  grep -Fqx '          DAILY_AMARU_STATE_DIR: ${{ runner.temp }}/daily-amaru' \
    <<<"$step" || return 1
  # shellcheck disable=SC2016
  grep -Fqx '          DAILY_AMARU_RECEIPT: ${{ runner.temp }}/daily-amaru/receipt' \
    <<<"$step" || return 1
}

allocation_boundary_holds "$daily_amaru" ||
  fail "runner-local paths are not bound after allocation in $daily_amaru:" \
    "$(job_level_runner_refs "$daily_amaru") job-level runner reference(s)"

# Restoring the exact two merged bindings, at the exact merged location.
# shellcheck disable=SC2016
merged_runner_regression='/^      DAILY_AMARU_MODE: production$/a\
      DAILY_AMARU_STATE_DIR: ${{ runner.temp }}/daily-amaru\
      DAILY_AMARU_RECEIPT: ${{ runner.temp }}/daily-amaru/receipt'

# shellcheck disable=SC2016
reject_mutant merged-runner-job-env.yaml "$daily_amaru" "$merged_runner_regression" \
  '      DAILY_AMARU_STATE_DIR: ${{ runner.temp }}/daily-amaru' \
  'the exact merged job-level runner bindings' allocation_boundary_holds
# shellcheck disable=SC2016
reject_mutant dropped-state-dir.yaml "$daily_amaru" \
  '/^          DAILY_AMARU_STATE_DIR: [$][{][{] runner[.]temp [}][}]\/daily-amaru$/d' \
  '!          DAILY_AMARU_STATE_DIR: ${{ runner.temp }}/daily-amaru' \
  'a controller that lost its runner-local state directory' \
  allocation_boundary_holds
# shellcheck disable=SC2016
reject_mutant relocated-receipt.yaml "$daily_amaru" \
  's|^          DAILY_AMARU_RECEIPT: [$][{][{] runner[.]temp [}][}]/daily-amaru/receipt$|          DAILY_AMARU_RECEIPT: /tmp/daily-amaru/receipt|' \
  '          DAILY_AMARU_RECEIPT: /tmp/daily-amaru/receipt' \
  'a receipt moved off runner-local storage' allocation_boundary_holds

printf 'ALLOCATION-BOUNDARY job_env_runner_refs=0 state_dir=1 receipt=1 mutants_rejected=3\n'
pass runner-paths-bound-after-allocation

# ---------------------------------------------------------------------------
# INV-219-02 / INV-219-03 — a complete census that cannot pass vacuously, and a
# validator that catches the incident class.
# ---------------------------------------------------------------------------

[ -x "$command_path" ] ||
  fail "the repository-wide validator is missing or not executable: $command_path"
[ -f "$actionlint_config" ] ||
  fail "the validator baseline is missing: $actionlint_config"
command -v actionlint >/dev/null 2>&1 ||
  fail 'actionlint is not on PATH; run this through just test-workflow-validation'

census=$(git ls-files '.github/workflows/*.yaml' '.github/workflows/*.yml' | sort -u)
expected_count=$(printf '%s\n' "$census" | grep -c . || true)
[ "$expected_count" -gt 0 ] ||
  fail 'the repository tracks no workflows, so a passing census would prove nothing'

validation_output="$tmp_root/validation.out"
if ! "$command_path" >"$validation_output" 2>&1; then
  cat "$validation_output" >&2
  fail 'repository-wide workflow validation failed on the tracked census'
fi

reported_count=$(sed -n 's/^WORKFLOW-VALIDATION count=\([0-9][0-9]*\) .*$/\1/p' \
  "$validation_output")
[ -n "$reported_count" ] ||
  fail 'passing validation output does not report a workflow count'
[ "$reported_count" -gt 0 ] ||
  fail 'validation reported a zero workflow count as a pass'
[ "$reported_count" -eq "$expected_count" ] ||
  fail "validated $reported_count workflows while the repository tracks $expected_count"

listed=$(grep -c '^workflow-census ' "$validation_output" || true)
[ "$listed" -eq "$expected_count" ] ||
  fail "the census listed $listed paths for $expected_count tracked workflows"
while IFS= read -r workflow; do
  seen=$(grep -Fxc "workflow-census $workflow" "$validation_output" || true)
  [ "$seen" -eq 1 ] ||
    fail "workflow validated $seen times instead of exactly once: $workflow"
done <<<"$census"

# A scratch repository runs the production command, unmodified, over a tracked
# file set this proof controls. Its own positive control has to go green first,
# so a red from a seeded defect is the defect and not the harness.
scratch_repo() {
  local root=$1
  mkdir -p "$root/.github/workflows" "$root/scripts"
  install -m 0755 "$command_path" "$root/scripts/check-github-actions.sh"
  cp "$actionlint_config" "$root/.github/actionlint.yaml"
  git -C "$root" init --quiet
  git -C "$root" config user.email 'issue-219-proof@invalid'
  git -C "$root" config user.name 'issue-219 proof'
}

scratch_validate() {
  local root=$1
  git -C "$root" add -A
  (cd "$root" && ./scripts/check-github-actions.sh) >"$root/out" 2>&1
}

harness_root="$tmp_root/harness-positive"
scratch_repo "$harness_root"
cp "$daily_amaru" "$harness_root/.github/workflows/daily-amaru.yaml"
scratch_validate "$harness_root" ||
  fail "the scratch harness cannot go green on the repaired workflow: $(cat "$harness_root/out")"
grep -q '^WORKFLOW-VALIDATION count=1 ' "$harness_root/out" ||
  fail 'the scratch harness did not report its single-workflow census'

empty_root="$tmp_root/empty-census"
scratch_repo "$empty_root"
if scratch_validate "$empty_root"; then
  fail 'an empty workflow census passed validation'
fi
grep -Fq 'empty workflow census' "$empty_root/out" ||
  fail "an empty census failed for the wrong reason: $(cat "$empty_root/out")"

# The baseline config is present in this scratch repository on purpose: a
# path-specific baseline must not be able to suppress the incident class.
regression_root="$tmp_root/merged-runner"
scratch_repo "$regression_root"
regression_workflow="$regression_root/.github/workflows/daily-amaru.yaml"
sed "$merged_runner_regression" "$daily_amaru" >"$regression_workflow"
# shellcheck disable=SC2016
grep -Fqx '      DAILY_AMARU_STATE_DIR: ${{ runner.temp }}/daily-amaru' \
  "$regression_workflow" ||
  fail 'mutation did not apply: merged job-level state directory binding'
# shellcheck disable=SC2016
grep -Fqx '      DAILY_AMARU_RECEIPT: ${{ runner.temp }}/daily-amaru/receipt' \
  "$regression_workflow" ||
  fail 'mutation did not apply: merged job-level receipt binding'
if scratch_validate "$regression_root"; then
  fail 'the validator accepted the exact merged runner-at-job-env defect'
fi
runner_diagnostics=$(grep -c 'context "runner" is not allowed here' \
  "$regression_root/out" || true)
[ "$runner_diagnostics" -eq 2 ] ||
  fail "expected both merged bindings diagnosed, got $runner_diagnostics"

printf 'WORKFLOW-CENSUS count=%d duplicates=0 validator=actionlint baseline=%s\n' \
  "$reported_count" "$actionlint_config"
printf 'WORKFLOW-MUTANTS exact_runner_job_env=reject empty_census=reject harness_positive=pass\n'
pass repository-wide-expression-census

# ---------------------------------------------------------------------------
# INV-219-04 — the guard is only worth its cost while a merge-required context
# still calls it. An orphaned command is red.
# ---------------------------------------------------------------------------

quality_job() {
  awk '
    $0 == "  code-quality:" { inside = 1; print; next }
    inside && /^  [A-Za-z0-9_-]+:/ { exit }
    inside { print }
  ' "$1"
}

required_caller_holds() {
  local job
  job=$(quality_job "$1")
  grep -Fqx '    name: Check code quality' <<<"$job" || return 1
  grep -Fqx "        run: $validator_command" <<<"$job" || return 1
}

required_caller_holds "$quality_workflow" ||
  fail "the required 'Check code quality' context does not run: $validator_command"

reject_mutant caller-commented.yaml "$quality_workflow" \
  "s|^        run: $validator_command\$|        # run: $validator_command|" \
  "        # run: $validator_command" \
  'a commented-out validator call' required_caller_holds
reject_mutant caller-removed.yaml "$quality_workflow" \
  "/^        run: $validator_command\$/d" \
  "!        run: $validator_command" \
  'a required context that no longer calls the validator' required_caller_holds
reject_mutant caller-renamed-context.yaml "$quality_workflow" \
  's/^    name: Check code quality$/    name: Check code quality (advisory)/' \
  '    name: Check code quality (advisory)' \
  'a validator call moved out of the merge-required context name' \
  required_caller_holds
reject_mutant caller-orphaned-job.yaml "$quality_workflow" \
  's/^  code-quality:$/  code-quality-disabled:/' \
  '  code-quality-disabled:' \
  'a validator call left in a disabled job' required_caller_holds

printf "REQUIRED-CALLER context='Check code quality' command=1 mutants_rejected=4\n"
pass validator-reachable-from-required-context

# ---------------------------------------------------------------------------
# FR-219-09 — the same command is reachable from the complete local gate, so
# the hosted context is not the only place the guard ever runs.
# ---------------------------------------------------------------------------

recipe_body() {
  awk -v name="$2" '
    $0 ~ "^" name ":" { inside = 1; next }
    inside && /^[^ \t]/ { exit }
    inside { print }
  ' "$1"
}

ci_line() {
  grep -E '^ci:' "$1" || true
}

local_ci_holds() {
  local line
  line=$(ci_line "$1")
  [ -n "$line" ] || return 1
  local dependency
  for dependency in check-workflows check-shell format-check \
    test-workflow-validation test-daily-amaru; do
    grep -Fq -- "$dependency" <<<"$line" || return 1
  done
}

# The exact recipe line, so a commented-out or shadowed invocation is not read
# as a call.
check_workflows_calls_validator() {
  recipe_body "$1" check-workflows | grep -Fqx "    ./$command_path"
}

local_ci_holds "$justfile_path" ||
  fail 'the local CI recipe does not cover the complete slice gate'
check_workflows_calls_validator "$justfile_path" ||
  fail "the check-workflows recipe does not run ./$command_path"

ci_without_validator="$mutant_root/justfile-ci-without-validator"
sed 's/^ci: .*$/ci: check-shell format-check test-workflow-validation test-daily-amaru/' \
  "$justfile_path" >"$ci_without_validator"
grep -Fqx 'ci: check-shell format-check test-workflow-validation test-daily-amaru' \
  "$ci_without_validator" ||
  fail 'mutation did not apply: local CI recipe without the validator'
if local_ci_holds "$ci_without_validator"; then
  fail 'the local gate check accepted a CI recipe that never validates workflows'
fi

reject_mutant justfile-check-workflows-noop "$justfile_path" \
  "s|^    ./$command_path\$|    true # ./$command_path|" \
  "    true # ./$command_path" \
  'a check-workflows recipe that runs nothing' check_workflows_calls_validator

printf 'LOCAL-CI ci_dependencies=5 validator_called=1 mutants_rejected=2\n'
pass validator-reachable-from-local-gate

printf 'WORKFLOW-VALIDATION-PROOF workflows=%d controls=4 mutants_rejected=9\n' \
  "$reported_count"
