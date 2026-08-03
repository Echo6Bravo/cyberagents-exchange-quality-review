# quality-review — a pre-submission quality gate for CyberAgents Exchange work

A Claude Code **skill** that runs an adversarial, proof-over-assertion quality and security
review of a cybersecurity agent / skill / MCP server **before** you push it publicly or submit
it to the [Tenable CyberAgents Exchange](https://exchange.tenable.com). It turns "did I miss
anything?" from a gut check into a repeatable checklist that finds the failure classes that
actually hurt a customer — and mirrors the Exchange's own reviewer checklist so you clear
review with fewer round-trips.

> This is a community contribution. It is **not** an official Tenable tool, and passing it is
> **not** a guarantee of Exchange acceptance — the live Exchange checklist and `validator.py`
> are always authoritative. The skill fetches and defers to them at review time.

## What it does

Invoke it (e.g. "run a quality review", or `/quality-review`) and it works 12 dimensions,
ranked by customer impact, reporting findings most-severe-first with a concrete repro and fix,
then an explicit **verdict** (ready, or the blocking items):

1. Detection false-negatives · 2. Injection/XSS · 3. Messy-data robustness · 4. Scale ·
5. Operational (exit codes / retry / determinism) · 6. Version portability · 7. Schema-drift ·
8. Secrets (full git history) · 9. Malicious/offensive self-check · 10. Undisclosed egress ·
11. Tests & CI · 12. Docs.

Plus a **Tenable Exchange submission** section that mirrors the live contributing checklist
(automated screening, listing requirements, listing↔repo congruence, outright-rejection gates).

For each dimension it **actually runs a probe** (adversarial input, a container, a scanner)
rather than reasoning about it. It leans on a standard toolkit where available —
**gitleaks** (full-history secret scan), **ruff** + **bandit** (Python lint/SAST),
**shellcheck**, **actionlint**, and **CodeQL** (as a GitHub Action) — and treats each as a
CI gate that must stay green.

## Install

Clone into your Claude Code skills directory:

```bash
# global (all projects)
git clone https://github.com/Echo6Bravo/quality-review-skill.git \
  ~/.claude/skills/quality-review

# or per-project
git clone https://github.com/Echo6Bravo/quality-review-skill.git \
  .claude/skills/quality-review
```

Then invoke it in Claude Code: **"run a quality review on this repo"** or `/quality-review`.
Skills follow the [Agent Skills](https://docs.anthropic.com/en/docs/claude-code/skills)
standard, so it also works in other assistants that support it.

## Optional tooling (the skill uses these if present)

```bash
brew install gitleaks ruff shellcheck actionlint   # macOS
pipx install bandit                                 # or: brew install bandit
```

CodeQL runs best as a GitHub Actions workflow (`github/codeql-action`), which is free for
public repositories and needs nothing installed locally.

## Prerequisites

- **Claude Code** (or another Agent-Skills-compatible assistant).
- **`gh`** (GitHub CLI) for the Exchange-submission checks (reading the live checklist/validator).
- The scanners above are optional — the skill degrades gracefully and notes what it couldn't run.

## CI

This repo runs the same gates it recommends (dimensions 8, 11, 18): **gitleaks** full-history
secret scan, **actionlint** on its own workflow, and a **SKILL.md structure check** (valid
`name`/`description` frontmatter, substantive body, all 18 dimensions present, no leftover
placeholders). See `.github/workflows/ci.yml`.

## Known limitations

- It is a **procedure that guides an assistant**, not a static analyzer — its thoroughness
  depends on the assistant executing the probes. Treat its verdict as a strong pre-check, not
  a certification.
- The Exchange checklist evolves; the copy embedded in `SKILL.md` is a snapshot. The skill
  fetches the live version and defers to it.
- It cannot replace the Exchange's **two-human reviewer** sign-off.

## License

[MIT](./LICENSE) © 2026 Tenable, Inc.
