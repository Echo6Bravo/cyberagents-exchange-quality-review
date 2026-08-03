# Changelog

All notable changes to this skill are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Two shipped helper scripts** (with tests, gated in CI):
  - `scripts/mutation-check.sh` — proves a regression test is a real guard, not a tautology:
    runs the test clean, mutates the guarded file, requires the test to FAIL, then restores.
    Mechanizes dimension 11's "revert the fix and confirm the test flips to fail."
  - `scripts/empty-relationship-scan.sh` — heuristic smell-finder for the `LOOKUP.get(k) or set()`
    fallthrough class that can leak a missing relationship past a gate (dimension 1).
- **Sharpened probes** distilled from real bugs found dogfooding the skill on a live tool:
  dim 1 gains a cross-variant silent-zero probe and an empty/absent-relationship probe; dim 4
  asks whether the code path used *at scale* is the one actually tested; dim 11 adds
  prove-the-test-isn't-a-tautology and synthetic-vs-live parity.

## [1.0.0] — 2026-08-03

Initial public release.

### Added
- `quality-review` skill (`SKILL.md`) — an 18-dimension adversarial pre-submission review gate
  for cybersecurity agents/skills/MCP servers, with a dedicated Tenable CyberAgents Exchange
  submission section mirroring the live reviewer checklist.
  - Core dimensions (1–12): detection false-negatives, injection/XSS, messy-data robustness,
    scale, operational, version portability & TLS, schema/contract drift, secrets (full git
    history + credential-at-rest), malicious/offensive self-check, undisclosed egress,
    tests & CI, docs.
  - LLM/AI-agent dimensions (13–18): indirect prompt-injection, AI data handling (at-rest &
    vendor egress), LLM output grounding & non-determinism, token/cost & loop controls,
    access control & agent authority, supply-chain provenance. These were derived from
    analyzing the live Exchange agent repositories, most of which are LLM/MCP agents.
- Up-front **coverage preflight**: reports which scanners are present and which dimensions
  run in degraded mode before producing a verdict.
- `setup.sh` — one-command install of the optional toolkit (`--check` reports without
  installing).
- CI that runs the same gates the skill recommends: gitleaks (full history), actionlint, and a
  SKILL.md structure check. CI actions are **pinned to commit SHAs** (dimension 18) with
  **Dependabot** wired to keep them current — practicing the skill's own no-moving-tags rule.
- Project docs: `SECURITY.md`, `CONTRIBUTING.md`, and an illustrative `examples/sample-review.md`.
