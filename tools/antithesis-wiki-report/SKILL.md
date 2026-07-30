---
name: antithesis-wiki-report
description: >
  Publish weekly Antithesis platform status reports to the
  cardano-node-antithesis GitHub wiki (pragma engagement). Use when asked
  to "upload the wiki report", "publish weekly Antithesis report",
  "Antithesis-Report", "platform status for pragma", or fill
  Antithesis-Reports. Report body format is owned by Antithesis — this skill
  only uploads. Runs tools/antithesis-wiki-report/scripts/upload-report.sh.
compatibility: Requires bash, git, gh (Write on the repo/wiki), GNU date.
metadata:
  version: "2026-07-30"
---

# Antithesis weekly wiki report (upload only)

Publishes **one markdown file per ISO week** to the project wiki:

- Index: https://github.com/cardano-foundation/cardano-node-antithesis/wiki/Antithesis-Reports
- Page: `Antithesis-Report-YYYY-Www`

**Cadence:** every **Thursday before the Discord meeting**. If missed, publish before the next meeting.

## Format — do not invent one

**Antithesis owns the report format.** They generate the weekly body with **their own skill / tooling**. This CF skill must **not**:

- Scaffold a CF template
- Rewrite their sections into a CF outline
- Ask them to match a CF layout

Only accept their markdown file, run safety checks, and publish it under the wiki naming convention.

This is **vendor status** (Antithesis / pragma), not the CF development logbook.

## Prerequisites

- **Write** on `cardano-foundation/cardano-node-antithesis` (wiki uses the same ACL)
- `gh auth login` (HTTPS) or SSH that can push to `*.wiki.git`
- Tools: `bash`, `git`, `gh`, GNU `date`, `sed`, `awk`
- A finished report file from **Antithesis's** skill (any markdown structure)

Install discoverability (optional, Claude Code):

```bash
# from repo root
mkdir -p ~/.claude/skills
ln -sfn "$(pwd)/tools/antithesis-wiki-report" ~/.claude/skills/antithesis-wiki-report
```

## Public-safety rules (enforced by the script)

1. **No authenticated Antithesis report URLs** (no query-string report links).
2. **No SSO cookies / PASETO / Bearer tokens.**
3. Use **run IDs** only; CF opens reports in the tenant UI.

`upload-report.sh check REPORT.md` validates before push; `publish` always checks.

## Workflow

### 1. Obtain their report body

They (or their agent) run **Antithesis-owned** tooling to produce `REPORT.md` in **their** format. Do not substitute a CF template.

### 2. Publish to the wiki

```bash
tools/antithesis-wiki-report/scripts/upload-report.sh publish \
  --week 2026-W31 \
  --authors "Luis Marcano (@LuisMarcano-antithesis)" \
  path/to/their-report.md
```

If the filename is already `Antithesis-Report-YYYY-Www.md`, `--week` can be omitted (inferred).

The script:

1. Safety-checks the body (does not rewrite structure)  
2. Clones the wiki shallowly via `gh`  
3. Writes `Antithesis-Report-YYYY-Www.md` (content as provided)  
4. Updates the index table on `Antithesis-Reports`  
5. Links the week in `_Sidebar`  
6. Commits and pushes  
7. Prints the wiki page URL (only that URL to the terminal)

Dry-run (no push):

```bash
tools/antithesis-wiki-report/scripts/upload-report.sh publish --dry-run --week 2026-W31 REPORT.md
```

## Agent procedure

When the user asks to upload a weekly Antithesis report:

1. Confirm **week** (`YYYY-Www`), **authors**, and path to **their** markdown body. Target **Thursday before Discord**.
2. Do **not** reformat into a CF template. If they have no body yet, tell them to run **their** Antithesis skill first — then upload.
3. Run `check`, then `publish` (ask before push if the environment is shared).
4. Reply with the bare wiki URL only (no markdown link wrapping).

Do **not** put report content in the CF `Logbook-*` pages.

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `ANTITHESIS_WIKI_REPO` | `cardano-foundation/cardano-node-antithesis` | `owner/repo` whose `.wiki` is updated |

## Files

| Path | Role |
|---|---|
| `scripts/upload-report.sh` | `publish` / `check` only (no CF template) |

## Related

- Wiki index (human): https://github.com/cardano-foundation/cardano-node-antithesis/wiki/Antithesis-Reports
- `tools/antithesis-overview/` — multi-run digest for CF triage; not the weekly status format
