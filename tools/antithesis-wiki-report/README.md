# antithesis-wiki-report

Upload **weekly Antithesis platform status** pages to the
[cardano-node-antithesis wiki](https://github.com/cardano-foundation/cardano-node-antithesis/wiki/Antithesis-Reports)
(pragma engagement).

**Cadence:** every **Thursday before the Discord meeting**.

**Format:** owned by Antithesis. Generate the body with **their** skill;
this tool only publishes the file, updates the index/sidebar, and enforces
public-safety checks. CF does not ship a report template.

## Quick start

```bash
# After Antithesis tooling wrote REPORT.md in their format:
./scripts/upload-report.sh publish \
  --week 2026-W31 \
  --authors "Your Name (@github)" \
  REPORT.md
```

Prints a single wiki URL on success.

## Safety

The script refuses bodies that look like authenticated Antithesis report
URLs or session material. Use **run IDs** only. Structure is left unchanged.

## Skill

See [SKILL.md](./SKILL.md) for agent instructions. Symlink into
`~/.claude/skills/antithesis-wiki-report` if you want slash-command discovery.
