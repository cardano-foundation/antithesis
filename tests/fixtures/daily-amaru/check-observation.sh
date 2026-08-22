#!/usr/bin/env bash
# Sourced by test-transport-boundary.sh for scenario check-observation.

# Scalars owned and assigned by that harness: the first row at harness file
# scope, the second rebound per scenario by prepare_case. Declaring them global
# states the contract for readers and static analysis without assigning it, so
# a scalar the harness stops providing still aborts on `set -u` instead of
# expanding empty. `-g` keeps them global whatever scope the source site is in.
# The harness also owns the boundary_seed_sources map read below.
declare -g workflow_head day foreign_sha tmp_root fixture_root transport
declare -g case_root bin effects receipt stdout stderr

obs_start=1000000
obs_candidate=$workflow_head

write_observation_time_tools() {
  local dest=$1
  rm -f "$dest/date" "$dest/sleep"
  cat >"$dest/date" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
clock=${DAILY_AMARU_OBSERVATION_CLOCK:?}
[ "${1:-}" = +%s ] || exit 64
cat "$clock"
EOF
  cat >"$dest/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
n=${1:?}
[[ "$n" =~ ^[1-9][0-9]*$ ]] || exit 64
log=${DAILY_AMARU_OBSERVATION_SLEEP_LOG:?}
clock=${DAILY_AMARU_OBSERVATION_CLOCK:?}
printf 'sleep %s\n' "$n" >>"$log"
now=$(cat "$clock")
printf '%s\n' "$((now + n))" >"$clock"
EOF
  chmod +x "$dest/date" "$dest/sleep"
}

setup_obs() {
  local label=$1
  prepare_case "$label"
  obs_root=$case_root/obs
  mkdir -p "$obs_root/polls"
  printf '0\n' >"$obs_root/poll"
  clock=$case_root/clock
  sleep_log=$case_root/sleep.log
  : >"$sleep_log"
  printf '%s\n' "$obs_start" >"$clock"
  write_observation_time_tools "$bin"
  rm -f "$bin/gh"
  ln -sf "$fixture_root/observation-gh.sh" "$bin/gh"
  [ -x "$bin/gh" ] || fail 'observation-gh stand-in is not executable'
}

write_duration_seconds() {
  local seconds=$1
  jq -n --argjson seconds "$seconds" '{
    workflow_runs: [{
      name: "Bootstrap CI",
      status: "completed",
      run_started_at: "2026-08-19T00:00:00Z",
      updated_at: (
        "2026-08-19T00:00:00Z"
        | fromdateiso8601 + $seconds
        | strftime("%Y-%m-%dT%H:%M:%SZ")
      )
    }]
  }' >"$obs_root/duration.json"
}

write_poll_empty() {
  local n=$1
  mkdir -p "$obs_root/polls/$n"
  printf '{"workflow_runs":[]}\n' >"$obs_root/polls/$n/runs.json"
}

write_poll_states() {
  local n=$1 spec name state head rest sep
  shift
  mkdir -p "$obs_root/polls/$n"
  jq -n --arg head "$obs_candidate" '{
    workflow_runs: [{
      name: "Bootstrap CI",
      check_suite_id: 10,
      head_sha: $head
    }]
  }' >"$obs_root/polls/$n/runs.json"
  {
    printf '{"check_runs":['
    sep=
    for spec in "$@"; do
      name=${spec%%|*}
      rest=${spec#*|}
      state=${rest%%|*}
      head=${rest#*|}
      if [ "$head" = "$rest" ]; then
        head=$obs_candidate
      fi
      case "$state" in
        success | failure | cancelled | timed_out)
          printf '%s{"name":"%s","head_sha":"%s","conclusion":"%s"}' \
            "$sep" "$name" "$head" "$state"
          ;;
        *)
          printf '%s{"name":"%s","head_sha":"%s","status":"%s","conclusion":null}' \
            "$sep" "$name" "$head" "$state"
          ;;
      esac
      sep=,
    done
    printf ']}\n'
  } >"$obs_root/polls/$n/checks-10.json"
}

write_all_success() {
  write_poll_states "$1" \
    'Build|success' \
    'Run unit Tests|success' \
    'Check code quality|success' \
    'publish-images|success'
}

write_all_pending() {
  write_all_lifecycle "$1" in_progress
}

write_all_lifecycle() {
  local n=$1 status=$2
  write_poll_states "$n" \
    "Build|$status" \
    "Run unit Tests|$status" \
    "Check code quality|$status" \
    "publish-images|$status"
}

pending_case_line='      queued | in_progress | waiting | pending | requested)'
pending_spellings=(queued in_progress waiting pending requested)

drop_pending_case_line() {
  local drop=$1 spelling sep=
  printf '      '
  for spelling in "${pending_spellings[@]}"; do
    [ "$spelling" = "$drop" ] && continue
    printf '%s%s' "$sep" "$spelling"
    sep=' | '
  done
  printf ')\n'
}

expected_success_rows() {
  printf 'Bootstrap CI|%s|%s|success\n' \
    Build "$obs_candidate" \
    'Run unit Tests' "$obs_candidate" \
    'Check code quality' "$obs_candidate" \
    publish-images "$obs_candidate"
}

count_head_polls() {
  grep -cE 'actions/runs[^[:space:]]*head_sha=' "$effects" || true
}

slept_total() {
  if [ ! -s "$sleep_log" ]; then
    printf '0\n'
    return
  fi
  awk '{ s += $2 } END { print s + 0 }' "$sleep_log"
}

assert_exclusive_obs_path() {
  local host_date=${boundary_seed_sources[date]:-}
  local host_sleep=${boundary_seed_sources[sleep]:-}
  [ "$PATH" = "$bin" ] || fail "observation PATH inherited host entries: $PATH"
  [ "$(command -v gh)" = "$bin/gh" ] || fail 'observation gh is not the stand-in'
  [ "$(command -v date)" = "$bin/date" ] || fail 'observation date is not the stand-in'
  [ "$(command -v sleep)" = "$bin/sleep" ] || fail 'observation sleep is not the stand-in'
  if [ -z "$host_date" ] || [ "$bin/date" -ef "$host_date" ]; then
    fail 'observation date inherited the host clock'
  fi
  if [ -z "$host_sleep" ] || [ "$bin/sleep" -ef "$host_sleep" ]; then
    fail 'observation sleep inherited the host sleeper'
  fi
}

run_obs() {
  local extra_transport=${1:-$transport}
  transport_rc=0
  DAILY_AMARU_DAY=$day \
    DAILY_AMARU_IDENTITY=boundary-bootstrap-token \
    GH_TOKEN=boundary-repository-token \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null \
    DAILY_AMARU_STATE_DIR=$state \
    DAILY_AMARU_RECEIPT=$receipt \
    DAILY_AMARU_BOUNDARY_GH_LOG=$effects \
    DAILY_AMARU_OBSERVATION_ROOT=$obs_root \
    DAILY_AMARU_OBSERVATION_CLOCK=$clock \
    DAILY_AMARU_OBSERVATION_SLEEP_LOG=$sleep_log \
    run_obs_command "$bin" "$extra_transport" require-bootstrap-checks \
      "$obs_candidate" >"$stdout" 2>"$stderr" || transport_rc=$?
}

run_obs_command() {
  local expected_bin=$1
  shift
  local PATH=$expected_bin
  export PATH
  hash -r
  assert_exclusive_obs_path
  "$@"
}

assert_no_real_effects() {
  if grep -Eq 'gh (pr create|repo clone|issue comment|workflow run|run watch)' \
    "$effects"; then
    fail "observation issued a real GitHub write/launch: $(tr '\n' ' ' <"$effects")"
  fi
}

apply_immediate_read_mutant() {
  local src=$1 dest=$2
  awk '
    $0 == "  require-bootstrap-checks)" {
      print
      print "    require_commands gh jq awk"
      print "    candidate=${1:?bootstrap candidate is required}"
      print "    checks=${DAILY_AMARU_BOOTSTRAP_CHECKS:-Build,Run unit Tests,Check code quality,publish-images}"
      print "    rows=$(collect_action_rows \"$bootstrap_repository\" \"$candidate\" \"$bootstrap_identity\")"
      print "    IFS='"'"','"'"' read -r -a required <<<\"$checks\""
      print "    for name in \"${required[@]}\"; do"
      print "      count=$(awk -F'"'"'|'"'"' -v n=\"$name\" -v h=\"$candidate\" \\"
      print "        '"'"'$2 == n && $3 == h && $4 == \"success\" { count++ } END { print count + 0 }'"'"' \\"
      print "        <<<\"$rows\")"
      print "      [ \"$count\" -eq 1 ] || die \"bootstrap check is not uniquely successful on $candidate: $name\""
      print "    done"
      print "    emit \"$rows\""
      inarm = 1
      next
    }
    inarm && $0 == "    ;;" { inarm = 0 }
    inarm { next }
    { print }
  ' "$src" >"$dest"
  chmod +x "$dest"
  # shellcheck disable=SC2016 # literal mutant source text; must not expand
  grep -Fq 'bootstrap check is not uniquely successful on $candidate: $name' \
    "$dest" || fail 'immediate-read mutation did not apply'
  # shellcheck disable=SC2016 # literal transport source text; must not expand
  if grep -Fq 'observe_bootstrap_checks "$candidate" "$bootstrap_identity"' \
    "$dest"; then
    fail 'immediate-read mutation left the bounded observer in the arm'
  fi
}

replace_unique_line() {
  local src=$1 dest=$2 old=$3 new=$4 label=$5
  [ "$(grep -Fxc "$old" "$src" || true)" -eq 1 ] ||
    fail "mutation seed is not unique: $label"
  awk -v old="$old" -v new="$new" '$0 == old { print new; next } { print }' \
    "$src" >"$dest"
  chmod +x "$dest"
  grep -Fqx "$new" "$dest" || fail "mutation did not apply: $label"
  ! grep -Fqx "$old" "$dest" || fail "mutation left the original line: $label"
}

assert_pending_lifecycle_success() {
  local spelling=$1 extra_transport=${2:-$transport}
  setup_obs "pending-$spelling"
  write_duration_seconds 4
  write_all_lifecycle 1 "$spelling"
  write_all_success 2
  run_obs "$extra_transport"
  [ "$transport_rc" -eq 0 ] ||
    fail "pending $spelling did not proceed: $(tr '\n' ' ' <"$stderr")"
  expected_success_rows >"$case_root/expected"
  cmp -s "$case_root/expected" "$stdout" ||
    fail "pending $spelling emitted non-exact success rows"
  grep -Fq 'not uniquely successful' "$stderr" &&
    fail "pending $spelling was classified as unique-success failure"
  grep -Fq 'never-reported' "$stderr" &&
    fail "pending $spelling was classified as terminal absence"
  grep -Fq 'bootstrap check failed' "$stderr" &&
    fail "pending $spelling was classified as failed"
  [ "$(count_head_polls)" -ge 2 ] ||
    fail "pending $spelling polls=$(count_head_polls), want >=2"
  assert_no_real_effects
}

reject_dropped_pending_spelling() {
  local spelling=$1 mutant new
  new=$(drop_pending_case_line "$spelling")
  mutant=$tmp_root/drop-$spelling.sh
  replace_unique_line "$transport" "$mutant" "$pending_case_line" "$new" \
    "drop-$spelling"
  setup_obs "drop-$spelling"
  write_duration_seconds 4
  write_all_lifecycle 1 "$spelling"
  write_all_success 2
  run_obs "$mutant"
  [ "$transport_rc" -ne 0 ] ||
    fail "dropping $spelling still treated it as non-terminal"
}

reject_parse_as_empty_census() {
  local mutant=$tmp_root/parse-as-empty.sh
  # shellcheck disable=SC2016 # literal transport source line; must not expand
  local old='    <<<"$runs") || return 1'
  # shellcheck disable=SC2016 # literal replacement line; must not expand
  local new='    <<<"$runs") || run_tsv='
  replace_unique_line "$transport" "$mutant" "$old" "$new" parse-as-empty
  setup_obs parse-as-empty
  write_duration_seconds 4
  : >"$obs_root/persist_malformed"
  run_obs "$mutant"
  [ "$transport_rc" -ne 0 ] || fail 'parse-as-empty mutant proceeded'
  grep -Fq 'never-reported' "$stderr" ||
    fail 'parse-as-empty mutant was not misclassified as never-reported'
  if grep -Fq 'transport-exhausted' "$stderr"; then
    fail 'parse-as-empty mutant still terminated as transport exhaustion'
  fi
}

reject_sleep_after_terminal_failure() {
  local mutant=$tmp_root/sleep-after-terminal-failure.sh
  # shellcheck disable=SC2016 # literal transport source line; must not expand
  local old='        die "bootstrap check failed on $candidate: $first_failed polls=$polls"'
  [ "$(grep -Fxc "$old" "$transport" || true)" -eq 1 ] ||
    fail 'failed-die line is not unique'
  awk -v old="$old" '
    $0 == old { print "        sleep 1" }
    { print }
  ' "$transport" >"$mutant"
  chmod +x "$mutant"
  [ "$(grep -Fxc '        sleep 1' "$mutant" || true)" -eq 1 ] ||
    fail 'sleep-after-terminal-failure mutation did not apply'
  setup_obs sleep-after-terminal-failure
  write_duration_seconds 4
  write_all_pending 1
  write_poll_states 2 \
    'Build|failure' \
    'Run unit Tests|in_progress' \
    'Check code quality|in_progress' \
    'publish-images|in_progress'
  run_obs "$mutant"
  [ "$transport_rc" -ne 0 ] ||
    fail 'sleep-after-terminal-failure mutant proceeded'
  [ "$(slept_total)" -gt 2 ] ||
    fail 'sleep-after-terminal-failure mutant did not sleep after the terminal census'
  [ "$(cat "$clock")" -gt $((obs_start + 2)) ] ||
    fail 'sleep-after-terminal-failure mutant did not advance the clock'
  [ "$(count_head_polls)" -eq 2 ] ||
    fail 'sleep-after-terminal-failure mutant added a later observation'
}

run_check_observation_proof() {
  local pending_success_polls=0 pending_failure_polls=0 absent_polls=0
  local duration_variants=0 slept_short=0 slept_long=0
  local failed_named=0 never_reported_named=0 transport_exhausted_named=0
  local transient_errors=0 persistent_errors=0 recovered=0
  local wrong_head_rejected=0 duplicate_rejected=0 partial_retried=0
  local all_success=0 immediate_read=pending fire4=pending
  local host_inherited=1 real_effects=1
  local mutant polls

  bind_boundary_sources

  setup_obs pending-success
  write_duration_seconds 4
  write_poll_empty 1
  write_all_success 2
  run_obs
  [ "$transport_rc" -eq 0 ] ||
    fail "pending→success did not proceed: $(tr '\n' ' ' <"$stderr")"
  expected_success_rows >"$case_root/expected"
  cmp -s "$case_root/expected" "$stdout" ||
    fail 'pending→success emitted non-exact success rows'
  grep -Fq 'not uniquely successful' "$stderr" &&
    fail 'not-yet-reported census was classified as unique-success failure'
  grep -Fq 'never-reported' "$stderr" &&
    fail 'not-yet-reported census was classified as terminal absence'
  pending_success_polls=$(count_head_polls)
  [ "$pending_success_polls" -ge 2 ] ||
    fail "pending→success polls=$pending_success_polls, want >=2"
  assert_no_real_effects

  setup_obs not-yet-negative
  write_duration_seconds 4
  write_poll_empty 1
  write_all_success 2
  run_obs
  [ "$transport_rc" -eq 0 ] ||
    fail "not-yet negative control failed: $(tr '\n' ' ' <"$stderr")"
  [ "$(count_head_polls)" -ge 2 ] ||
    fail 'not-yet negative control used a single observation'
  grep -Fq 'not uniquely successful' "$stderr" &&
    fail 'not-yet negative control reproduced the one-shot diagnostic'
  assert_no_real_effects

  grep -Fqx "$pending_case_line" "$transport" ||
    fail 'accepted pending lifecycle spellings drifted from the proof census'
  for spelling in "${pending_spellings[@]}"; do
    assert_pending_lifecycle_success "$spelling"
  done

  setup_obs pending-failure
  write_duration_seconds 4
  write_all_pending 1
  write_poll_states 2 \
    'Build|failure' \
    'Run unit Tests|in_progress' \
    'Check code quality|in_progress' \
    'publish-images|in_progress'
  run_obs
  [ "$transport_rc" -ne 0 ] || fail 'pending→failure proceeded'
  grep -Eq 'bootstrap check failed on '"$obs_candidate"': Build( |$)' \
    "$stderr" ||
    fail "pending→failure lacked named failed diagnostic: $(tr '\n' ' ' <"$stderr")"
  grep -Fq 'never-reported' "$stderr" &&
    fail 'concluded failure was named never-reported'
  pending_failure_polls=$(count_head_polls)
  [ "$pending_failure_polls" -eq 2 ] ||
    fail "pending→failure polls=$pending_failure_polls, want 2"
  [ "$(slept_total)" -eq 2 ] ||
    fail "pending→failure slept=$(slept_total) after the terminal census, want 2"
  [ "$(cat "$clock")" -eq $((obs_start + 2)) ] ||
    fail "pending→failure clock=$(cat "$clock") after the terminal census, want $((obs_start + 2))"
  failed_named=1
  assert_no_real_effects

  setup_obs absent-short
  write_duration_seconds 4
  write_poll_empty 1
  write_poll_empty 2
  write_poll_empty 3
  write_poll_empty 4
  write_poll_empty 5
  run_obs
  [ "$transport_rc" -ne 0 ] || fail 'never-reporting check proceeded'
  grep -Eq 'bootstrap check never-reported on '"$obs_candidate"': Build polls=[0-9]+' \
    "$stderr" ||
    fail "absence lacked never-reported diagnostic: $(tr '\n' ' ' <"$stderr")"
  absent_polls=$(count_head_polls)
  [ "$absent_polls" -ge 2 ] || fail "absent polls=$absent_polls, want >=2"
  slept_short=$(slept_total)
  [ "$slept_short" -eq 4 ] ||
    fail "4s duration slept=$slept_short, want 4"
  never_reported_named=1
  assert_no_real_effects

  setup_obs absent-long
  write_duration_seconds 10
  write_poll_empty 1
  write_poll_empty 2
  write_poll_empty 3
  write_poll_empty 4
  write_poll_empty 5
  run_obs
  [ "$transport_rc" -ne 0 ] || fail 'long never-reporting check proceeded'
  grep -Fq 'never-reported' "$stderr" ||
    fail 'long absence lacked never-reported'
  slept_long=$(slept_total)
  [ "$slept_long" -eq 10 ] ||
    fail "10s duration slept=$slept_long, want 10"
  [ "$slept_short" -ne "$slept_long" ] ||
    fail 'observation window ignored injected duration evidence'
  duration_variants=2
  assert_no_real_effects

  setup_obs transient
  write_duration_seconds 4
  printf '1\n' >"$obs_root/fault-1"
  write_all_success 2
  run_obs
  [ "$transport_rc" -eq 0 ] ||
    fail "transient transport did not recover: $(tr '\n' ' ' <"$stderr")"
  expected_success_rows >"$case_root/expected"
  cmp -s "$case_root/expected" "$stdout" ||
    fail 'transient recovery emitted non-exact success rows'
  grep -Fq 'bootstrap check failed' "$stderr" &&
    fail 'transient transport was classified as check failure'
  transient_errors=1
  recovered=1
  assert_no_real_effects

  setup_obs persistent
  write_duration_seconds 4
  : >"$obs_root/persist_fault"
  run_obs
  [ "$transport_rc" -ne 0 ] || fail 'persistent transport proceeded'
  grep -Eq 'bootstrap check transport-exhausted on '"$obs_candidate"' polls=[0-9]+' \
    "$stderr" ||
    fail "persistent transport lacked exhaustion diagnostic: $(tr '\n' ' ' <"$stderr")"
  grep -Fq 'never-reported' "$stderr" &&
    fail 'transport exhaustion was named never-reported'
  grep -Fq 'bootstrap check failed' "$stderr" &&
    fail 'transport exhaustion was named check failure'
  [ "$(count_head_polls)" -ge 2 ] ||
    fail 'persistent transport did not retry inside the window'
  persistent_errors=1
  transport_exhausted_named=1
  assert_no_real_effects

  setup_obs wrong-head
  write_duration_seconds 4
  write_poll_states 1 \
    "Build|success|$foreign_sha" \
    "Run unit Tests|success|$foreign_sha" \
    "Check code quality|success|$foreign_sha" \
    "publish-images|success|$foreign_sha"
  write_poll_states 2 \
    "Build|success|$foreign_sha" \
    "Run unit Tests|success|$foreign_sha" \
    "Check code quality|success|$foreign_sha" \
    "publish-images|success|$foreign_sha"
  write_poll_states 3 \
    "Build|success|$foreign_sha" \
    "Run unit Tests|success|$foreign_sha" \
    "Check code quality|success|$foreign_sha" \
    "publish-images|success|$foreign_sha"
  write_poll_states 4 \
    "Build|success|$foreign_sha" \
    "Run unit Tests|success|$foreign_sha" \
    "Check code quality|success|$foreign_sha" \
    "publish-images|success|$foreign_sha"
  write_poll_states 5 \
    "Build|success|$foreign_sha" \
    "Run unit Tests|success|$foreign_sha" \
    "Check code quality|success|$foreign_sha" \
    "publish-images|success|$foreign_sha"
  run_obs
  [ "$transport_rc" -ne 0 ] || fail 'wrong-head success rows proceeded'
  [ ! -s "$stdout" ] || fail 'wrong-head success rows emitted a value'
  wrong_head_rejected=1
  assert_no_real_effects

  setup_obs duplicate
  write_duration_seconds 4
  write_poll_states 1 \
    'Build|success' \
    'Build|success' \
    'Run unit Tests|success' \
    'Check code quality|success' \
    'publish-images|success'
  run_obs
  [ "$transport_rc" -ne 0 ] || fail 'duplicate success rows proceeded'
  grep -Eq 'bootstrap check failed on '"$obs_candidate"': Build' "$stderr" ||
    fail "duplicate rows lacked failed diagnostic: $(tr '\n' ' ' <"$stderr")"
  duplicate_rejected=1
  assert_no_real_effects

  setup_obs partial
  write_duration_seconds 4
  write_poll_states 1 \
    'Build|success' \
    'Run unit Tests|success' \
    'Check code quality|success'
  write_all_success 2
  run_obs
  [ "$transport_rc" -eq 0 ] ||
    fail "partial census did not retry to success: $(tr '\n' ' ' <"$stderr")"
  [ "$(count_head_polls)" -ge 2 ] || fail 'partial census did not retry'
  expected_success_rows >"$case_root/expected"
  cmp -s "$case_root/expected" "$stdout" ||
    fail 'partial retry emitted non-exact success rows'
  partial_retried=1
  assert_no_real_effects

  setup_obs all-success
  write_all_success 1
  run_obs
  [ "$transport_rc" -eq 0 ] ||
    fail "unique all-success failed: $(tr '\n' ' ' <"$stderr")"
  expected_success_rows >"$case_root/expected"
  cmp -s "$case_root/expected" "$stdout" ||
    fail 'unique all-success emitted non-exact rows'
  [ "$(count_head_polls)" -eq 1 ] ||
    fail 'unique all-success waited after a complete census'
  all_success=1
  assert_no_real_effects
  real_effects=0
  host_inherited=0

  mutant=$tmp_root/immediate-read.sh
  apply_immediate_read_mutant "$transport" "$mutant"
  setup_obs fire4-mutant
  write_duration_seconds 4
  write_poll_empty 1
  write_all_success 2
  run_obs "$mutant"
  [ "$transport_rc" -ne 0 ] || fail 'immediate-read mutant proceeded on a missing census'
  grep -Fq "bootstrap check is not uniquely successful on $obs_candidate: Build" \
    "$stderr" ||
    fail "immediate-read mutant missed fire-4 fingerprint: $(tr '\n' ' ' <"$stderr")"
  [ "$(count_head_polls)" -eq 1 ] ||
    fail 'immediate-read mutant executed more than one census'
  immediate_read=rejected
  fire4=not-yet-reported

  for spelling in "${pending_spellings[@]}"; do
    reject_dropped_pending_spelling "$spelling"
  done
  reject_sleep_after_terminal_failure

  setup_obs malformed
  write_duration_seconds 4
  : >"$obs_root/persist_malformed"
  run_obs
  [ "$transport_rc" -ne 0 ] || fail 'malformed transport proceeded'
  grep -Eq 'bootstrap check transport-exhausted on '"$obs_candidate"' polls=[0-9]+' \
    "$stderr" ||
    fail "malformed transport lacked exhaustion diagnostic: $(tr '\n' ' ' <"$stderr")"
  grep -Fq 'never-reported' "$stderr" &&
    fail 'malformed transport was named never-reported'
  grep -Fq 'bootstrap check failed' "$stderr" &&
    fail 'malformed transport was named check failure'
  [ "$(count_head_polls)" -ge 2 ] ||
    fail 'malformed transport did not retry inside the window'
  assert_no_real_effects
  reject_parse_as_empty_census

  [ "$pending_success_polls" -ge 2 ] &&
    [ "$pending_failure_polls" -ge 2 ] &&
    [ "$absent_polls" -ge 2 ] &&
    [ "$duration_variants" -ge 2 ] ||
    fail 'observation counters were not derived from executed polls'
  printf 'CHECK-OBSERVATION pending_success_polls=%s pending_failure_polls=%s absent_polls=%s duration_variants=%s\n' \
    "$pending_success_polls" "$pending_failure_polls" "$absent_polls" \
    "$duration_variants"
  printf 'CHECK-TERMINALS failed_named=%s never_reported_named=%s transport_exhausted_named=%s\n' \
    "$failed_named" "$never_reported_named" "$transport_exhausted_named"
  printf 'CHECK-TRANSPORT transient_errors=%s persistent_errors=%s recovered=%s\n' \
    "$transient_errors" "$persistent_errors" "$recovered"
  printf 'CHECK-EXACT wrong_head_rejected=%s duplicate_rejected=%s partial_retried=%s all_success=%s\n' \
    "$wrong_head_rejected" "$duplicate_rejected" "$partial_retried" \
    "$all_success"
  printf 'CHECK-MUTANT immediate_read=%s fire4=%s\n' \
    "$immediate_read" "$fire4"
  printf 'CHECK-BOUNDARY real_effects=%s host_inherited=%s\n' \
    "$real_effects" "$host_inherited"
}

# --- issue #231: fault-labeling completeness at every observation boundary ---

# The census is derived from production, never hand-listed. The body of
# collect_action_rows is folded into logical lines, and every logical line that
# reaches an external API or a JSON parser must be immediately preceded by the
# marker naming its boundary. A call site added without a marker, or with a
# marker naming a boundary the stand-in cannot inject, cannot produce a census
# matching the injectable registry.
derive_boundary_census() {
  local script=$1
  awk '
    function handle(text,   name, kind, mode) {
      if (text ~ /^observation_boundary [A-Za-z0-9_-]+$/) {
        if (pending != "") {
          print "ERROR unconsumed-boundary-marker " pending
          bad = 1
          exit
        }
        name = text
        sub(/^observation_boundary /, "", name)
        if (name in seen) {
          print "ERROR duplicate-boundary-marker " name
          bad = 1
          exit
        }
        seen[name] = 1
        pending = name
        return
      }
      kind = ""
      if (text ~ /(^|[^A-Za-z0-9_-])gh api([^A-Za-z0-9_-]|$)/) {
        kind = "api"
      }
      if (text ~ /(^|[^A-Za-z0-9_-])jq([^A-Za-z0-9_-]|$)/) {
        if (kind != "") {
          print "ERROR ambiguous-boundary-call-site " substr(text, 1, 48)
          bad = 1
          exit
        }
        kind = "parse"
      }
      if (kind == "") {
        return
      }
      if (pending == "") {
        print "ERROR unmarked-boundary-call-site " substr(text, 1, 48)
        bad = 1
        exit
      }
      mode = pending
      sub(/^.*-/, "", mode)
      if (mode != kind) {
        print "ERROR boundary-mode-mismatch " pending " " kind
        bad = 1
        exit
      }
      print pending " " kind
      pending = ""
    }
    /^collect_action_rows[a-z_]*\(\) \{$/ {
      if (pending != "") {
        print "ERROR unconsumed-boundary-marker " pending
        bad = 1
        exit
      }
      inside = 1
      next
    }
    inside && $0 == "}" { inside = 0; next }
    !inside { next }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (buffer == "" && line ~ /^#/) {
        next
      }
      buffer = (buffer == "" ? line : buffer " " line)
      if (buffer ~ /\\$/) {
        sub(/\\$/, "", buffer)
        next
      }
      if (buffer ~ /(\|\||&&)$/) {
        next
      }
      handle(buffer)
      buffer = ""
    }
    END {
      if (bad) {
        exit
      }
      if (buffer != "") {
        handle(buffer)
      }
      if (bad) {
        exit
      }
      if (pending != "") {
        print "ERROR unconsumed-boundary-marker " pending
      }
    }
  ' "$script"
}

# The injectable registry comes from the stand-in's implemented endpoint
# classes, in a different file from the production census the comparison judges.
derive_injectable_boundaries() {
  local class
  local -a classes=()
  mapfile -t classes < <(awk '
    /^[[:space:]]*inject_boundary_fault [A-Za-z0-9_-]+$/ { print $2 }
  ' "$fixture_root/observation-gh.sh" | sort -u)
  [ "${#classes[@]}" -gt 0 ] || return 1
  for class in "${classes[@]}"; do
    printf '%s-api api\n%s-parse parse\n' "$class" "$class"
  done
}

boundary_census_matches_registry() {
  local script=$1 derived injectable
  derived=$(derive_boundary_census "$script")
  if grep -q '^ERROR ' <<<"$derived"; then
    return 1
  fi
  injectable=$(derive_injectable_boundaries) || return 1
  [ "$(sort <<<"$derived")" = "$(sort <<<"$injectable")" ]
}

insert_after_unique_line() {
  local src=$1 dest=$2 anchor=$3 label=$4
  shift 4
  local inserted line
  [ "$(grep -Fxc "$anchor" "$src" || true)" -eq 1 ] ||
    fail "mutation anchor is not unique: $label"
  inserted=$(printf '%s\n' "$@")
  awk -v anchor="$anchor" -v inserted="$inserted" '
    { print }
    $0 == anchor { print inserted }
  ' "$src" >"$dest"
  chmod +x "$dest"
  for line in "$@"; do
    [ "$(grep -Fxc "$line" "$dest" || true)" -ge 1 ] ||
      fail "mutation did not apply: $label"
  done
  [ "$(wc -l <"$dest")" -eq "$(($(wc -l <"$src") + $#))" ] ||
    fail "mutation applied an unexpected line count: $label"
}

# One persistent fault at one derived boundary, held for the whole
# duration-derived window. Every poll's census is incomplete, so a fault the
# transport swallows surfaces as never-reported rather than as success.
observation_boundary_fault_case() {
  local boundary=$1 kind=$2 script=$3 copy=${4:-}
  local n polls
  boundary_case_exhausted=0
  boundary_case_named=0
  setup_obs "boundary-$boundary"
  write_duration_seconds 4
  for n in 1 2 3 4 5 6; do
    write_all_pending "$n"
  done
  printf '%s\n' "$boundary" >"$obs_root/boundary-fault"
  run_obs "$script"
  [ -z "$copy" ] || cp "$stderr" "$copy"
  [ "$transport_rc" -ne 0 ] ||
    fail "persistent $kind fault at $boundary proceeded to success"
  grep -Fq 'never-reported' "$stderr" &&
    fail "persistent $kind fault at $boundary was named never-reported"
  grep -Fq 'bootstrap check failed' "$stderr" &&
    fail "persistent $kind fault at $boundary was named a check failure"
  grep -Eq "bootstrap check transport-exhausted on $obs_candidate polls=[0-9]+" \
    "$stderr" && boundary_case_exhausted=1
  [ "$boundary_case_exhausted" -eq 1 ] ||
    fail "persistent $kind fault at $boundary lacked transport exhaustion: $(tr '\n' ' ' <"$stderr")"
  grep -Eq "bootstrap check transport-exhausted on $obs_candidate polls=[0-9]+ boundary=$boundary\$" \
    "$stderr" && boundary_case_named=1
  [ "$boundary_case_named" -eq 1 ] ||
    fail "persistent $kind fault at $boundary exhausted without naming it: $(tr '\n' ' ' <"$stderr")"
  grep -Fq "observation-gh: injected fault boundary=$boundary" "$effects" ||
    fail "persistent $kind fault at $boundary never reached its boundary"
  polls=$(count_head_polls)
  [ "$polls" -ge 2 ] ||
    fail "persistent $kind fault at $boundary polls=$polls, want >=2"
  assert_no_real_effects
}

# A survivor is killed when the exact assertion the candidate passes fails on
# the mutant, and fails for the defect the mutant encodes: a boundary fault
# mapped to a valid empty census, which the observer then calls never-reported.
reject_boundary_survivor() {
  local label=$1 boundary=$2 kind=$3 mutant=$4
  local stderr_copy=$tmp_root/survivor-$label.stderr
  local log=$tmp_root/survivor-$label.log
  if (observation_boundary_fault_case "$boundary" "$kind" "$mutant" \
    "$stderr_copy") >"$log" 2>&1; then
    fail "survivor mutant $label retained the named-exhaustion behavior"
  fi
  [ -f "$stderr_copy" ] ||
    fail "survivor mutant $label produced no observation to judge"
  grep -Fq 'never-reported' "$stderr_copy" ||
    fail "survivor mutant $label did not reproduce the mapping-to-empty defect: $(tr '\n' ' ' <"$stderr_copy")"
  grep -Fq 'transport-exhausted' "$stderr_copy" &&
    fail "survivor mutant $label still exhausted the transport"
  return 0
}

reject_added_boundary_mutants() {
  local mutant anchor='  local runs workflow suite run_head jobs run_tsv'

  mutant=$tmp_root/added-boundary-marked.sh
  # shellcheck disable=SC2016 # literal inserted source lines; must not expand
  insert_after_unique_line "$transport" "$mutant" "$anchor" \
    added-boundary-marked \
    '  observation_boundary extra-api' \
    '  with_identity "$identity" gh api "repos/$target_repository" >/dev/null ||' \
    '    return 1'
  if boundary_census_matches_registry "$mutant"; then
    fail 'census accepted an added API boundary with no injected case'
  fi

  mutant=$tmp_root/added-boundary-unmarked.sh
  # shellcheck disable=SC2016 # literal inserted source lines; must not expand
  insert_after_unique_line "$transport" "$mutant" "$anchor" \
    added-boundary-unmarked \
    '  with_identity "$identity" gh api "repos/$target_repository" >/dev/null ||' \
    '    return 1'
  if boundary_census_matches_registry "$mutant"; then
    fail 'census accepted an unnamed added API boundary'
  fi
}

# Byte-identical to the archived submission-2 auditor payloads.
apply_jobs_parse_as_empty_mutant() {
  local dest=$1
  # shellcheck disable=SC2016 # literal source/replacement lines; must not expand
  replace_unique_line "$transport" "$dest" \
    '      <<<"$jobs" || return 1' \
    '      <<<"$jobs" || true # mutant maps malformed check-runs JSON to empty' \
    jobs-parse-as-empty
}

apply_jobs_api_as_empty_mutant() {
  local dest=$1
  awk '
    /check-suites\/\$suite\/check-runs\?per_page=100"\) \|\|$/ {
      print
      getline
      if ($0 != "      return 1") exit 73
      print "      jobs='\''{\"check_runs\":[]}'\''"
      changed++
      next
    }
    { print }
    END { if (changed != 1) exit 74 }
  ' "$transport" >"$dest" ||
    fail 'jobs-api-as-empty mutation seed drifted'
  chmod +x "$dest"
  [ "$(grep -Fxc '      jobs='\''{"check_runs":[]}'\''' "$dest" || true)" -eq 1 ] ||
    fail 'jobs-api-as-empty mutation did not apply'
}

run_check_observation_boundaries_proof() {
  local derived injectable derived_count name kind mutant
  local nonzero=0 malformed=0 exhausted=0 named=0
  local added_boundary_mutant=pending survivor_mutants=pending
  local receipt_unwritable=pending receipt_stale=pending
  local receipt_absent=pending out_of_band_mutant=pending
  local -a injected=()

  bind_boundary_sources

  derived=$(derive_boundary_census "$transport")
  ! grep -q '^ERROR ' <<<"$derived" ||
    fail "boundary census is underived: $(tr '\n' ' ' <<<"$derived")"
  injectable=$(derive_injectable_boundaries) ||
    fail 'observation stand-in implements no injectable boundary class'
  [ "$(sort <<<"$derived")" = "$(sort <<<"$injectable")" ] ||
    fail "derived census and injectable registry disagree: derived=[$(tr '\n' ';' <<<"$derived")] injectable=[$(tr '\n' ';' <<<"$injectable")]"
  derived_count=$(grep -c . <<<"$derived")
  [ "$derived_count" -gt 0 ] || fail 'derived boundary census is empty'

  while read -r name kind; do
    [ -n "$name" ] || continue
    observation_boundary_fault_case "$name" "$kind" "$transport"
    injected+=("$name")
    exhausted=$((exhausted + boundary_case_exhausted))
    named=$((named + boundary_case_named))
    case "$kind" in
      api) nonzero=$((nonzero + 1)) ;;
      parse) malformed=$((malformed + 1)) ;;
      *) fail "unusable derived boundary kind: $kind" ;;
    esac
  done <<<"$derived"

  [ "$(printf '%s\n' "${injected[@]}" | sort)" = \
    "$(awk '{ print $1 }' <<<"$derived" | sort)" ] ||
    fail 'executed injections did not cover the derived census'

  reject_added_boundary_mutants
  added_boundary_mutant=rejected

  mutant=$tmp_root/jobs-parse-as-empty.sh
  apply_jobs_parse_as_empty_mutant "$mutant"
  reject_boundary_survivor jobs-parse-as-empty check-runs-parse parse "$mutant"

  mutant=$tmp_root/jobs-api-as-empty.sh
  apply_jobs_api_as_empty_mutant "$mutant"
  reject_boundary_survivor jobs-api-as-empty check-runs-api api "$mutant"
  survivor_mutants=killed

  observation_boundary_receipt_case unwritable unwritable runs-api "$transport"
  receipt_unwritable=named
  observation_boundary_receipt_case stale stale runs-api "$transport"
  receipt_stale=named
  observation_boundary_receipt_case absent absent check-runs-parse "$transport"
  receipt_absent=named
  reject_out_of_band_boundary_record
  out_of_band_mutant=rejected

  printf 'CHECK-OBSERVATION-BOUNDARY-CENSUS derived=%s injected=%s added_boundary_mutant=%s\n' \
    "$derived_count" "${#injected[@]}" "$added_boundary_mutant"
  printf 'CHECK-OBSERVATION-BOUNDARY-FAULTS nonzero=%s malformed=%s exhausted=%s named=%s survivor_mutants=%s\n' \
    "$nonzero" "$malformed" "$exhausted" "$named" "$survivor_mutants"
  printf 'CHECK-OBSERVATION-BOUNDARY-RECEIPT unwritable=%s stale=%s absent=%s out_of_band_mutant=%s\n' \
    "$receipt_unwritable" "$receipt_stale" "$receipt_absent" \
    "$out_of_band_mutant"
}

# The boundary receipt must not depend on state that can fail or go stale at
# runtime. Each case sabotages the out-of-band record path the rejected
# submission-1 candidate relied on, and still requires the exact latest failing
# boundary to be named. `unnamed` is never an acceptable receipt.
observation_boundary_receipt_case() {
  local label=$1 record_state=$2 boundary=$3 script=$4 copy=${5:-}
  local n polls
  setup_obs "receipt-$label"
  write_duration_seconds 4
  for n in 1 2 3 4 5 6; do
    write_all_pending "$n"
  done
  case "$record_state" in
    unwritable) mkdir "$state/observation-boundary" ;;
    stale) printf 'check-runs-parse\n' >"$state/observation-boundary" ;;
    absent) rm -rf "$state/observation-boundary" ;;
    *) fail "unusable boundary record state: $record_state" ;;
  esac
  printf '%s\n' "$boundary" >"$obs_root/boundary-fault"
  run_obs "$script"
  [ -z "$copy" ] || cp "$stderr" "$copy"
  [ "$transport_rc" -ne 0 ] ||
    fail "$label receipt case proceeded to success"
  grep -Fq 'boundary=unnamed' "$stderr" &&
    fail "$label receipt fell back to an unnamed boundary: $(tr '\n' ' ' <"$stderr")"
  grep -Eq "bootstrap check transport-exhausted on $obs_candidate polls=[0-9]+ boundary=$boundary\$" \
    "$stderr" ||
    fail "$label receipt did not name $boundary: $(tr '\n' ' ' <"$stderr")"
  grep -Fq "observation-gh: injected fault boundary=$boundary" "$effects" ||
    fail "$label receipt case never reached its boundary"
  polls=$(count_head_polls)
  [ "$polls" -ge 2 ] ||
    fail "$label receipt case polls=$polls, want >=2"
  assert_no_real_effects
}

# Reintroduce the rejected candidate's mechanism as a one-line mutation: read
# the receipt from the out-of-band record instead of from the failure the
# caller just observed. An unwritable record must not erase the boundary and a
# stale record must not rename it.
reject_out_of_band_boundary_record() {
  local mutant=$tmp_root/out-of-band-boundary-record.sh
  local record_state log
  # shellcheck disable=SC2016 # literal source/replacement lines; must not expand
  replace_unique_line "$transport" "$mutant" \
    '      last_boundary=$(observation_boundary_receipt "$rows")' \
    '      last_boundary=$(cat "$state_dir/observation-boundary" 2>/dev/null || true)' \
    out-of-band-boundary-record
  for record_state in unwritable stale; do
    log=$tmp_root/out-of-band-$record_state.stderr
    if (observation_boundary_receipt_case "out-of-band-$record_state" \
      "$record_state" runs-api "$mutant" "$log") \
      >"$tmp_root/out-of-band-$record_state.log" 2>&1; then
      fail "out-of-band boundary record survived a $record_state record"
    fi
  done
}
