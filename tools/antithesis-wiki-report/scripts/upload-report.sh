#!/usr/bin/env bash
# Publish an Antithesis weekly platform report to the
# cardano-node-antithesis GitHub wiki.
#
# Report body format is owned by Antithesis (their skill/tooling).
# This script only safety-checks and uploads the file as-is.
#
# Usage:
#   upload-report.sh publish [--week YYYY-Www] [--authors "..."] [--status filled] [--dry-run] REPORT.md
#   upload-report.sh check  REPORT.md
#
# Requires: bash, git, gh (authenticated with write access to the wiki),
#           GNU date, sed, awk, mktemp.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

DEFAULT_OWNER_REPO="cardano-foundation/cardano-node-antithesis"
OWNER_REPO="${ANTITHESIS_WIKI_REPO:-$DEFAULT_OWNER_REPO}"
WIKI_REMOTE="https://github.com/${OWNER_REPO}.wiki.git"
INDEX_PAGE="Antithesis-Reports.md"
SIDEBAR="_Sidebar.md"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "$*" >&2; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

# ISO week string YYYY-Www for a given day (default: today UTC).
current_week() {
  date -u +%G-W%V
}

# Validate YYYY-Www
parse_week() {
  local w=$1
  [[ "$w" =~ ^([0-9]{4})-W([0-9]{2})$ ]] || die "week must be YYYY-Www (got: $w)"
  local year=${BASH_REMATCH[1]}
  # force base-10 (avoid 08/09 octal)
  local week=$((10#${BASH_REMATCH[2]}))
  (( week >= 1 && week <= 53 )) || die "ISO week out of range: $w"
  WEEK_YEAR=$year
  WEEK_NUM=$week
  WEEK_LABEL=$(printf '%s-W%02d' "$year" "$week")
}

# Monday..Sunday (UTC labels) of an ISO week. Uses GNU date + Jan-4 rule.
week_period() {
  local year=$1 week=$2
  local d u mon sun
  d=$(date -ud "${year}-01-04 +$((week - 1)) weeks" +%F)
  u=$(date -ud "$d" +%u)
  mon=$(date -ud "$d -$((u - 1)) days" +%F)
  sun=$(date -ud "$mon +6 days" +%F)
  PERIOD="${mon} → ${sun}"
}

page_name() {
  echo "Antithesis-Report-${WEEK_LABEL}.md"
}

# Reject authenticated report URLs / obvious secrets in body.
check_content() {
  local file=$1
  [[ -f "$file" ]] || die "file not found: $file"
  local bad=0

  if grep -nE 'antithesis\.com/report/[^[:space:]]+\?' "$file" >/dev/null 2>&1; then
    info "forbidden: authenticated Antithesis report URL (query string / token)"
    grep -nE 'antithesis\.com/report/' "$file" >&2 || true
    bad=1
  fi
  if grep -nE '(PASETO|__Host-antithesis_sso_session|Bearer [A-Za-z0-9._-]{20,})' "$file" >/dev/null 2>&1; then
    info "forbidden: session cookie / bearer / PASETO material"
    bad=1
  fi
  if grep -nE 'token=[A-Za-z0-9._%-]{16,}' "$file" >/dev/null 2>&1; then
    info "forbidden: URL token= parameter"
    bad=1
  fi
  if (( bad )); then
    die "report fails public-safety checks — use run IDs only, no report tokens"
  fi
  info "check: ok ($file)"
}

# Ensure index table has a row for this week; set status/authors when publishing.
update_index() {
  local wiki=$1 authors=$2 status=$3
  local index="${wiki}/${INDEX_PAGE}"
  [[ -f "$index" ]] || die "missing ${INDEX_PAGE} in wiki clone — run CF setup first"

  week_period "$WEEK_YEAR" "$WEEK_NUM"
  local page link authors_cell
  page=$(page_name)
  page=${page%.md}
  link="[${WEEK_LABEL}](${page})"
  authors_cell=${authors:-—}

  if grep -qE "Antithesis-Report-${WEEK_LABEL}|\]\(Antithesis-Report-${WEEK_LABEL}\)" "$index"; then
    # Rewrite the matching table row (best-effort; keeps other rows intact).
    awk -v week="$WEEK_LABEL" -v link="$link" -v period="$PERIOD" \
        -v authors="$authors_cell" -v status="$status" '
      BEGIN { OFS="" }
      {
        if ($0 ~ ("\\[?" week "\\]?") && $0 ~ /^\|/) {
          printf "| %s | %s | %s | %s |\n", link, period, authors, status
          next
        }
        print
      }
    ' "$index" >"${index}.tmp"
    mv "${index}.tmp" "$index"
    info "index: updated row for $WEEK_LABEL"
  else
    # Insert a new row after the header separator line of the Index table.
    awk -v row="| ${link} | ${PERIOD} | ${authors_cell} | ${status} |" '
      BEGIN { done=0 }
      {
        print
        if (!done && /^\|---/) {
          # first separator after "| Week |" — insert after it
          if (prev ~ /Week/) {
            print row
            done=1
          }
        }
        prev=$0
      }
      END {
        if (!done) {
          print row > "/dev/stderr"
          exit 1
        }
      }
    ' "$index" >"${index}.tmp" || die "could not insert index row (table shape unexpected)"
    mv "${index}.tmp" "$index"
    info "index: added row for $WEEK_LABEL"
  fi
}

update_sidebar() {
  local wiki=$1
  local sidebar="${wiki}/${SIDEBAR}"
  [[ -f "$sidebar" ]] || die "missing ${SIDEBAR} in wiki clone"
  local page
  page=$(page_name)
  page=${page%.md}

  if grep -qF "Antithesis-Report-${WEEK_LABEL}" "$sidebar"; then
    info "sidebar: already lists $WEEK_LABEL"
    return
  fi

  # Ensure year section + week bullet under **Antithesis reports**.
  if ! grep -qF '**Antithesis reports**' "$sidebar"; then
    cat >>"$sidebar" <<EOF

**Antithesis reports**

- [Index](Antithesis-Reports)
- ${WEEK_YEAR}
  - [W$(printf '%02d' "$WEEK_NUM")](${page})
EOF
    info "sidebar: created Antithesis reports section"
    return
  fi

  if grep -qE "^- ${WEEK_YEAR}\$" "$sidebar"; then
    # Insert week bullet after the year line (or after existing weeks for that year).
    awk -v year="$WEEK_YEAR" -v num="$(printf '%02d' "$WEEK_NUM")" -v page="$page" '
      BEGIN { in_year=0; done=0 }
      {
        if ($0 ~ ("^- " year "$")) {
          print
          in_year=1
          next
        }
        if (in_year && $0 ~ /^  - \[W/) {
          print
          next
        }
        if (in_year && !done) {
          printf "  - [W%s](%s)\n", num, page
          done=1
          in_year=0
        }
        if ($0 ~ /^\*\*/ || $0 ~ /^- [0-9]{4}$/) {
          if (in_year && !done) {
            printf "  - [W%s](%s)\n", num, page
            done=1
            in_year=0
          }
        }
        print
      }
      END {
        if (in_year && !done) {
          printf "  - [W%s](%s)\n", num, page
        }
      }
    ' "$sidebar" >"${sidebar}.tmp"
    mv "${sidebar}.tmp" "$sidebar"
  else
    # Append year block at end of Antithesis section (end of file is fine).
    cat >>"$sidebar" <<EOF
- ${WEEK_YEAR}
  - [W$(printf '%02d' "$WEEK_NUM")](${page})
EOF
  fi
  info "sidebar: linked $WEEK_LABEL"
}

clone_wiki() {
  local dest=$1
  need git
  need gh
  info "cloning wiki ${OWNER_REPO}.wiki → $dest"
  # gh uses the caller's credentials; works for HTTPS wiki remotes.
  if ! gh repo clone "${OWNER_REPO}.wiki" "$dest" -- --depth 1 2>/dev/null; then
    # Fallback: some gh versions want the bare .wiki URL via git.
    git clone --depth 1 "$WIKI_REMOTE" "$dest" \
      || die "failed to clone wiki (need Write on ${OWNER_REPO} and gh auth)"
  fi
}

publish() {
  local report=$1 authors=$2 status=$3 dry_run=$4
  [[ -f "$report" ]] || die "report not found: $report"
  check_content "$report"

  local tmp page
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  clone_wiki "$tmp/wiki"
  page=$(page_name)
  cp -- "$report" "$tmp/wiki/${page}"
  update_index "$tmp/wiki" "$authors" "$status"
  update_sidebar "$tmp/wiki"

  git -C "$tmp/wiki" add -- "$page" "$INDEX_PAGE" "$SIDEBAR"
  if git -C "$tmp/wiki" diff --cached --quiet; then
    info "nothing to commit (wiki already up to date)"
  else
    local msg
    msg="report: Antithesis platform ${WEEK_LABEL}"
    if [[ -n "$authors" ]]; then
      msg+=" (${authors})"
    fi
    git -C "$tmp/wiki" -c user.useConfigOnly=false \
      commit -m "$msg" \
      || die "commit failed (set git user.name / user.email if needed)"
  fi

  local url="https://github.com/${OWNER_REPO}/wiki/${page%.md}"

  if (( dry_run )); then
    info "dry-run: not pushing. Local clone: $tmp/wiki"
    info "would publish: $url"
    # keep tree for inspection — disable cleanup
    trap - EXIT
    return 0
  fi

  git -C "$tmp/wiki" push origin HEAD \
    || die "push failed — confirm Write access on ${OWNER_REPO}"
  info "published: $url"
  echo "$url"
}

usage() {
  cat <<EOF
Usage:
  $(basename "$0") publish [--week YYYY-Www] [--authors NAME] [--status TEXT] [--dry-run] REPORT.md
  $(basename "$0") check   REPORT.md

Report body format is owned by Antithesis — pass the markdown their skill produced.
This tool only uploads as-is (plus public-safety checks) and updates the wiki index.

Environment:
  ANTITHESIS_WIKI_REPO   default ${DEFAULT_OWNER_REPO}

Wiki pages:
  Antithesis-Report-YYYY-Www.md   weekly report body (their format)
  Antithesis-Reports.md           index table
  _Sidebar.md                     navigation
EOF
}

main() {
  need bash
  need date
  need sed
  need awk
  need mktemp

  local cmd=${1:-}
  [[ -n "$cmd" ]] || { usage; exit 2; }
  shift || true

  local week="" week_explicit=0 authors="" status="filled" dry_run=0 report=""

  case "$cmd" in
    publish)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --week) week=$2; week_explicit=1; shift 2 ;;
          --authors) authors=$2; shift 2 ;;
          --status) status=$2; shift 2 ;;
          --dry-run) dry_run=1; shift ;;
          -h|--help) usage; exit 0 ;;
          --) shift; break ;;
          -*) die "unknown flag: $1" ;;
          *)
            if [[ -z "$report" ]]; then
              report=$1; shift
            else
              die "unexpected argument: $1"
            fi
            ;;
        esac
      done
      ;;
    check)
      report=${1:-}
      [[ -n "$report" ]] || die "check requires REPORT.md"
      check_content "$report"
      exit 0
      ;;
    init)
      die "init removed: Antithesis owns the report format. Generate the body with their skill, then: $0 publish REPORT.md"
      ;;
    -h|--help|help) usage; exit 0 ;;
    *) die "unknown command: $cmd (try publish|check)" ;;
  esac

  [[ -n "$report" ]] || die "publish requires REPORT.md"
  if (( ! week_explicit )) && [[ "$report" =~ Antithesis-Report-([0-9]{4}-W[0-9]{2})\.md$ ]]; then
    week="${BASH_REMATCH[1]}"
  fi

  if [[ -z "$week" ]]; then
    week=$(current_week)
  fi
  parse_week "$week"

  publish "$report" "$authors" "$status" "$dry_run"
}

main "$@"
