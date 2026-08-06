# Contributing

Contributions are welcome. This skill holds itself to the bar it asks of others, so a PR is
expected to keep that bar green.

## Before opening a PR

- **Structure:** `SKILL.md` stays at the repo root with valid `name`/`description` YAML
  frontmatter and all numbered dimensions present (the CI `skill-structure` job enforces this).
- **Lint your changes:** `bash setup.sh --check` to see your toolkit, then run the relevant
  scanners — `actionlint` on any workflow change, `shellcheck -S warning scripts/*.sh setup.sh`
  on shell changes.
- **Test the shipped scripts:** `bash scripts/test_scripts.sh` must be green. A new scanner in
  `scripts/` needs its scenarios registered there — the CI shellcheck glob and this one entry
  point pick it up with no workflow change, so there is nothing else to wire.
- **Prove your new test is a real guard** (the skill's own dimension 11): break the thing it
  checks and confirm the test *fails*. A test that passes either way asserts nothing. If your
  change documents a limitation — a known false positive, a blind spot — add a test that pins it,
  so a later "improvement" can't silently change the documented behaviour.
- **`semgrep` changes:** rules live in `scripts/semgrep-rules` and are authored in-repo. Don't add
  `--config p/<pack>` (the hosted registry isn't part of this toolkit), and don't add a rule for
  something `bandit` already catches — the lanes are deliberately non-overlapping so a finding is
  never counted twice. See the toolkit table in the README.
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
