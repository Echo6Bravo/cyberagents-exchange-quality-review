# Contributing

Contributions are welcome. This skill holds itself to the bar it asks of others, so a PR is
expected to keep that bar green.

## Before opening a PR

- **Structure:** `SKILL.md` stays at the repo root with valid `name`/`description` YAML
  frontmatter and all numbered dimensions present (the CI `skill-structure` job enforces this).
- **Lint your changes:** `bash setup.sh --check` to see your toolkit, then run the relevant
  scanners — `actionlint` on any workflow change, `shellcheck -S warning setup.sh` on shell
  changes.
- **No secrets, ever:** the CI runs `gitleaks` over full history and will fail the build on any
  finding. Never commit a token, key, or real assessment data.
- **CI must be green.** Don't merge a red pipeline — that's dimension 11 of the skill itself.

## What good changes look like

- **New/changed dimensions:** justify them (ideally with evidence, like the LLM dimensions
  which came from analyzing real Exchange agents). Keep them proof-oriented ("run a probe, don't
  eyeball") and note when a dimension is N/A rather than padding a review.
- **Docs:** keep the README and `CHANGELOG.md` in sync with behavior; don't overclaim (the skill
  is a pre-check, not a certification).

## Versioning

This project uses [Semantic Versioning](https://semver.org/) and a
[Keep a Changelog](https://keepachangelog.com/) `CHANGELOG.md`. Note user-facing changes under
an "Unreleased" heading in your PR.
