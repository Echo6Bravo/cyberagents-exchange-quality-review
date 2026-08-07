# Contributing

Contributions are welcome. This skill holds itself to the bar it asks of others, so a PR is
expected to keep that bar green.

## Before opening a PR

- **Structure:** `SKILL.md` stays at the repo root with valid `name`/`description` YAML
  frontmatter and all numbered dimensions present (the CI `skill-structure` job enforces this).
- **Lint your changes:** `bash setup.sh --check` to see your toolkit, then run the relevant
  scanners — `actionlint` on any workflow change, `shellcheck -S warning scripts/*.sh setup.sh`
  on shell changes, and **`ruff check .` on any Python change, including a semgrep fixture**.
  Fixtures are not exempt: the defect a fixture plants is a *security* shape, not a formatting one.
  If a lint rule genuinely conflicts with the planted defect, silence it with a narrow
  `# noqa: <code>` naming the reason — never widen an exclude, which blinds the check to the next
  file. `ruff` runs in CI pinned, so a fixture that fails it fails the build.
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
  never counted twice. See the toolkit table in the README. Concretely, `bandit` owns these and a
  semgrep rule for the **Python** form of any of them would be a duplicate (each verified by running
  `bandit` against a probe file, not assumed from its docs):

  | Construct | bandit | Severity |
  |---|---|---|
  | `hashlib.md5` / `sha1` | B324 | HIGH |
  | `random` for a security value | B311 | LOW |
  | `pickle.loads` | B301 | MEDIUM |
  | `yaml.load` with an unsafe loader | B506 | MEDIUM |
  | `requests(..., verify=False)` | B501 | HIGH |

  The TypeScript equivalents are fair game and several already exist, because `bandit` and `ruff`
  cannot parse TS at all. **A new rule needs four things:** a sibling fixture with the same basename
  (the runner requires it — rule and fixture flat in one directory), `# ruleid:` annotations plus at
  least two *unannotated* near-misses (`semgrep test` requires the reported lines to equal the
  annotated lines exactly, so near-misses are enforced true negatives), a documented
  false-positive/blind-spot list in the rule header, and **Gate 5 mutation rows in
  `scripts/test_scripts.sh`** — the coverage check fails the build if a rule has none.
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
