# Security Policy

## Reporting a vulnerability

If you find a security issue in this skill — for example, guidance that could cause a
reviewer to run an unsafe command, or a flaw in `setup.sh` — please report it privately:

- Open a **GitHub Security Advisory** on this repository
  ([Security → Advisories → Report a vulnerability](https://github.com/Echo6Bravo/cyberagents-exchange-quality-review/security/advisories/new)), or
- Open a regular issue **only if it is not sensitive**.

Please include: what the problem is, how to reproduce it, and the impact. Expect an initial
response within a few days. Please do not disclose publicly until a fix is available.

## Scope

This repository ships **instructions** (a Claude Code skill, `SKILL.md`) and a small
`setup.sh` installer — there is no long-running service or network endpoint. Relevant
concerns are therefore:

- **`setup.sh`** — it installs developer tooling via Homebrew/pipx. Report anything that
  could cause it to install or execute unexpected/untrusted content.
- **`SKILL.md` guidance** — report any instruction that could lead an assistant to take an
  unsafe action (e.g. running a destructive or credential-exposing command).

Out of scope: issues in the third-party scanners the skill recommends (gitleaks, ruff, bandit,
shellcheck, actionlint, CodeQL) — report those to their respective projects.

## Good hygiene when using this skill

- The skill installs software **only with your approval**; review what `setup.sh` runs.
- It is a pre-submission *pre-check*, not a security certification or an official Tenable tool.
