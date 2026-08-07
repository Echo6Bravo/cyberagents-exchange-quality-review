# Changelog

All notable changes to this skill are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **`scripts/tautology-scan.sh`** — heuristic grep over *test files* for assertions carrying an
  `or not <precondition>` escape hatch (dimension 11). This is the tautology shape
  `mutation-check.sh` structurally cannot find: the escape lives in the test, so no mutation to the
  code under test changes the outcome. Verified on the four shapes it must catch and four negative
  controls; measured against two real repos (1 hit across 11 test files, 0 in a repo with none),
  and that single hit is a documented question-not-a-defect. Known false positives and two known
  blind spots (an `or not` wrapped onto a continuation line, and assertions over derived
  properties) are documented in the script header and **locked by tests**, so widening the regex
  fails CI until the header is updated in the same commit.
- **Dimension 11 gains both tautology shapes in prose**: the `or not` escape hatch, and assertions
  over a *derived* property (`@property`, `cached_property`, getter, serializer formula), which
  re-implement the derivation and pass on every input. The second is deliberately not automated —
  it needs a human to answer "is this field authored data or computed?".

- **`scripts/semgrep-rules/` — 10 authored rules**, each a rule + planted-defect fixture pair, covering
  dimensions 2, 6, 8, 11, 13, and 17. Seven are **JS/TS**, which `ruff` and `bandit` cannot parse at
  all: credentials in `localStorage`/`chrome.storage.local` (8), `rejectUnauthorized: false` (6),
  wildcard CORS and `listen(…, "0.0.0.0")` (17), scanned data interpolated into an LLM `system:`
  prompt in the Anthropic and OpenAI shapes (13), `eval`/`new Function`/an explicitly unsafe js-yaml
  schema (2), and `md5`/`sha1`/`Math.random()` used for a security value (8). Two Python rules cover
  test-quality shapes no scanner owns — `.islower()` used as a case check (`False` for `"123"`) and a
  negative control whose "invalid" input is built by a `.replace()` that silently did nothing — plus
  one for a file write with no resolved containment guard.
  The hosted registry is **not** used: rules are local so each maps to a numbered dimension and to
  this skill's severity rubric, and the registry is frequently unreachable behind a corporate TLS
  proxy with no bounded timeout on the fetch. **No rule duplicates `bandit`** — which is why the TLS,
  crypto, and deserialization rules are TypeScript-only, and why the skill now credits `bandit`'s
  Python coverage (B301/B311/B324/B501/B506) *conditionally*, since it is an optional tool.
  Every rule header documents its measured false positives and blind spots, and several deliberately
  trade recall for a hit list a human will actually read (bare `Math.random()` is ignored on purpose).
- **Six CI gates on the rules themselves**, because installing semgrep is not the same as gaining
  coverage and every failure mode here is a *silent zero*. `semgrep test` exits 0 when it finds no
  fixtures at all, and `semgrep validate` exits 0 while printing "Configuration is invalid" — so the
  gates read output, never exit codes. Gate 4 proves the gates fire by breaking a rule with the
  documented unquoted-colon gotcha and requiring the gates to fail. **Gate 5 applies dimension 11 to
  the rules reflexively**: for each of 40 rows it mutates the fixture to remove one defect and
  requires exactly one finding to disappear, plus negative-control rows that mutate an incidental
  value and require the finding to *remain*. A rule that survives its own defect removal is matching
  the file, not the defect — and Gate 5 has its own negative control proving it catches that.
- **Measured false-positive bounds, stated as bounds.** Beyond the fixtures, the rules were run
  against 1138 real JS/TS files (~392k lines): 30 findings in 15 files, all genuine instances of the
  flagged construct, 14 of the 15 files vendored third-party code. Two caveats ship with that number
  because a bare zero would overclaim: three rules found nothing on a corpus containing **no
  instances of what they look for** (a true negative with no discriminating power), and vendored
  bundles dominate the `eval`/`new Function` hits, so scans should be scoped to first-party source.
- **`setup.sh` installs and reports `semgrep`**, as a **three-state** tool: missing /
  present-but-no-rules (**reported as contributing no coverage**) / present with the skill's own
  rules. semgrep ships no bundled security rules, so "binary present" is not coverage — reporting
  it as present-and-done would be exactly the overclaiming this skill flags in others. The state is
  determined by looking for `scripts/semgrep-rules`, **not** by probing the network: `curl` can
  reach `semgrep.dev` while semgrep's own fetch still fails (different trust stores), and the
  config fetch has no bounded timeout.

- **`scripts/pinned-vuln-scan.py`** — checks whether exactly-pinned dependencies are *known
  vulnerable*, via the GitHub Advisory DB through `gh` (dimension 18). Dimension 18 previously
  reviewed only whether deps were **pinned**, which is the opposite failure and says nothing about
  this: a pin reproduces whatever it was, including reproducibly vulnerable, and never drifts onto a
  fix. Uses `gh` because it is already a stated prerequisite — `pip-audit`/`osv-scanner` would be new
  installs, and the GitHub API is reachable on networks where semgrep's registry and CodeQL packs
  are TLS-proxy-blocked. Exit codes carry the anti-silent-zero contract: 0 clean, 1 found,
  **2 could not complete** (no manifests, no exact pins, or every lookup failed), and internally a
  failed lookup returns `None` where "asked, nothing known" returns `[]` — collapsing those two is
  how an outage becomes a clean bill of health. Range specifiers (`^1.2.3`) are deliberately
  excluded as dimension 18's *other* finding, so the same defect is never counted twice.
  - **The version comparator is hand-rolled on purpose.** `packaging` was measured importable on
    only **1 of 4** interpreters on this machine, and a probe that dies on `ImportError` reports
    nothing. It is instead used as a *test-time oracle*: **144,199 ordered pairs, 100.0000%
    agreement**, plus the semver.org §11 normative precedence chain as a second, independent oracle
    (the npm `semver` package was unavailable — the registry returns 403 by policy). Reconciling
    both is what forces `a`/`b`/`c` to share ranks with `alpha`/`beta`/`rc` rather than sorting
    alphabetically, and the one divergence — a bare numeric tail like `1.7.1-2` is a *post*-release
    in PEP440 and a *pre*-release in semver — is documented where it is decided.
  - **The range grammar was enumerated, not assumed:** 1122 real ranges across 43 packages use
    exactly five forms, and `<= V` + `>= V, <= V` are **15%** of them, so a `>=`/`<`-only
    implementation is silently wrong on one range in seven. All five are tested. Dedupe happens
    **after** range matching because the same GHSA is published against multiple branches with
    different ranges (`GHSA-34jh-p97f-mpxf` is both `< 1.26.19` and `>= 2.0.0, < 2.2.2`), so
    counting nodes instead of advisories inflates the finding count.
  - **Its own test suite was mutation-tested to 28/28** over three rounds, and every round found a
    real gap rather than confirming the suite: an early version missed the exact `beta.1`/`beta.8`
    collapse the oracle had caught, and a later one stayed green while the corpus invariant check
    was disabled — 736 assertions asserting nothing, because nothing tests a test. That audit is now
    a named function checked against planted violations with a negative control. One survivor was
    resolved by *deleting* code proven inert (identical output on 276,396 pairs) rather than adding
    a test for it. **The negative is stated as a bound:** `ecosystem: ACTIONS` returns nothing, so
    pinned CI actions are uncovered, and transitive deps count only where a lockfile pins them.
  - **The self-test is offline because every `gh` path is stubbed — verified with egress blocked.**
    One assertion had been sending a deliberately invalid ecosystem to the real API on the belief
    that `gh` would reject it locally. It does not: there is no local GraphQL schema, so that was a
    live round-trip on every CI run, and it returned `None` for whichever of three reasons applied
    first (invalid enum, `gh` unauthenticated, network unreachable) — in CI always the second, so it
    never exercised the path its own comment described. A test that passes for a reason you did not
    intend is dimension 11's tautology, found by asking why a green assertion was green. Replaced
    with a stub `gh` that exits non-zero, and the whole suite is now confirmed passing with all
    egress blackholed rather than merely claimed to be offline.
  - **Measured against live data, which found a false negative the fixtures did not.** Run against
    real manifests, it missed all 12 pins in a `uv pip compile --generate-hashes` file: the trailing
    ` \` before the `--hash` lines defeated the version regex's end anchor. That is the strictest
    pinning style there is, so the best-pinned repos were the ones being reported as having nothing
    to check — an unearned clean. Fixed and pinned by a test. On live API data the found-path was
    then verified end to end: **38 findings across 7 packages, all 38 independently re-derived**
    (every flagged pin genuinely satisfies the cited range *and* sorts below the cited fix, 0
    violations), with a negative control confirming a pin above the fix version drops to exit 0 and
    `^4.17.1` correctly excluded as a range rather than a pin.
- **CI now runs `ruff` (pinned), which it had been recommending without running.** Found the way
  these things should be found: three `UP031` findings had been sitting in a shipped semgrep fixture
  because nothing linted it. The README listed `ruff` in the toolkit and claimed this repo runs the
  gates it recommends, so its absence was an overstated coverage claim — dimension 12's own failure
  mode, committed here. The semgrep fixtures are deliberately **in** scope: the defect each one plants
  is a security shape, not a formatting one, so a conflict gets a narrow `# noqa: <code>` with its
  reason rather than a widened exclude. Verified with a negative control (percent-format restored →
  "Found 3 errors", exit 1). `ruff`'s `S` rules stay off, as everywhere: `bandit` owns that lane.

### Changed
- The shipped-helper directives and the CI comment no longer hardcode how many scripts ship
  ("these two" → "every script in `scripts/`"), so adding a scanner cannot leave a stale count.
- `setup.sh` now derives its brew list, its non-brew fallback list, and its status report from a
  single `TOOLS` variable. Previously four hand-maintained copies had to agree; editing one without
  the others meant a tool could install but never appear in the coverage report.

### Fixed
- `setup.sh --check` could **hang indefinitely**: it ran `<tool> --version` for each tool, and
  `semgrep --version` performs a network update check that never returns on a network that
  blackholes it (measured: >90s, no output, until killed). Version probes now pass
  `--disable-version-check` for semgrep and are wrapped in a 10s timeout for every tool, so one
  unresponsive binary degrades to `version probe timed out` instead of stalling the report.
  Verified with a stub whose `--version` sleeps 300s: the report completed in 14s.

## [1.1.0] — 2026-08-04

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
- **Dimension 19 — execution-scope correctness**, in a new conditional "generated artifacts"
  section for tools that *emit* something a human or CI later runs (remediation scripts, IaC,
  SQL, playbooks, config). Distinct from every existing dimension because the failure is not an
  error but a **wrong success**: an artifact spanning more scope than its tooling can address in
  one invocation resolves identifiers against whichever scope the runner is authenticated to.
  Derived from a real defect — Terraform/OpenTofu `import` blocks for two AWS accounts in one
  file, where a same-named table in the wrong account would be adopted and reconfigured while
  the plan reported success. Covers hard-vs-soft scope boundaries, failing closed on a scope
  mismatch instead of trusting a filename, visibly-marked unfinished values, and validating each
  emitted file in isolation with the real parser.
- **Further probes from the same dogfooding round:**
  - dim 4 — *fixed-text amplification*: measure bytes **per item at two scales**, not total
    bytes; flat bytes/item means boilerplate is being re-emitted per item instead of per group
    or per run. Includes the hoist-by-consequence rule (reference detail may move to a companion
    file; irreversibility/cost/blast-radius warnings stay inline) and the like-for-like
    measurement caveat — the originating case measured 14% at 1k items and 48% at 50k, and the
    growth with scale is the signal a single measurement cannot show.
  - dim 11 — *never weaken a security assertion to make a feature pass*: when a legitimate
    change trips a safety blocklist, replace the blanket ban with an exact allowlist that stays
    accounted for, rather than loosening the pattern.
  - dim 11 — *correlated synthetic fixtures*: axes generated from one loop counter
    (`account = i % 40`, `region = i % 4`) silently couple, so combination-dependent behavior is
    never exercised and measurements taken on them flatter the code.

- **A defined severity taxonomy** — Critical / High / Medium / Low / Informational, scored on
  *consequence* rather than effort to fix, with a table of what belongs at each level and which
  levels block shipping. The skill previously said "most severe first" without ever defining the
  levels, so nothing was labeled: an efficiency observation and a leaked credential both read as
  "a finding." **Efficiency and other non-security findings are now Informational by default**
  and never blocking; promoting one requires naming the consequence (a breached documented limit,
  a real resource exhausted at the tool's claimed scale, or volume that defeats review). Dim 4
  and dim 19 carry their own severity guidance, including that a *hard*-boundary scope span is
  Critical while a *soft*-boundary one is Informational.
- **Three output buckets — rejection gates → defects → informational.** The `## Output` section is
  restructured around *who decides and against what standard*, rather than by topic. Topic buckets
  ("security" / "best practice" / "efficiency") fail because findings belong to two at once — an
  uncapped LLM pagination loop is simultaneously a cost and a security problem — while there is
  only one question that determines where it goes: does it block? Serves both audiences: a
  reviewer reads bucket 1 to decide accept/reject and can stop; a contributor reads buckets 2–3
  for the fix list.
  - **Rejection gates** are *pulled* verbatim from the live Exchange checklist and are binary with
    **no severity** — the checklist says a detected credential is "an immediate rejection," so
    there is no *how bad*. A failed gate sets the verdict to NOT READY on its own.
  - **Defects** carry a severity, and **every severity must cite its basis** (an Exchange checklist
    item, a CodeQL `security-severity` score, a scanner rule plus its own rating, or the rubric
    row). An unsourced label is how an unexamined guess acquires the appearance of authority.
  - **A scanner rating is evidence that may raise but never lower a finding.** Verified, not
    assumed: `bandit` rates a hardcoded password (B105 → CWE-259) **LOW/MEDIUM**, the exact class
    the Exchange rejects outright; `gitleaks` 8.30.1 emits no severity at all; `ruff` has no
    severity field. Only CodeQL exposes a real score. So scanner output cannot be the severity
    source. Believing a scanner finding unreachable is a *note on* it, not a downgrade.
  - **CWE is an optional classification field, not the severity source.** Considered as the source
    of truth for defect severity and rejected on two grounds. First, coverage: CWE maps cleanly or
    partially to 11 of the 19 dimensions and has no honest entry for 8 of them, including dim 1
    (a detector silently missing an in-scope finding — the skill's highest-ranked dimension), dim
    11 (a regression test that asserts nothing), dim 19 (an artifact targeting the wrong account)
    and dim 9 (weaponized intent) — CWE catalogs *code weaknesses*, which those are not. Second,
    and decisively: CWE is a taxonomy, not a scale — the hardcoded password above *has* a CWE and
    is still rated LOW by the tool that assigned it. So the guidance is to cite a CWE where a real
    one fits, and to state "no applicable CWE" where none does, because a wrong-but-official-looking
    label misdirects triage worse than an absent one.
- **CI enforcement of the bucket structure, each check proven with a negative control**
  (dimension 11 applied to this repo): the three buckets must be present *and in order*; the
  cite-your-basis, raise-but-never-lower, and CWE-is-optional rules must remain stated; and
  `examples/sample-review.md` must keep severity labels inside the Defects bucket only, cite a
  basis there, and carry at least one. Every check was verified to fail when the thing it guards
  is removed — including two controls that were themselves mis-specified and corrected rather
  than accepted as passes.

### Changed
- Toolkit guidance on `bandit` B101: scope the skip to tests rather than repo-wide, and treat an
  `assert` in library/runtime code as a finding — `python -O` strips it, so an assert-protected
  invariant is unenforced in exactly the optimized build where violating it does damage.
  (Verified: `python3 -O` returns `-5` from a function whose `assert x > 0` should have rejected it.)
- CI structure check and README now assert **19** dimensions, that all five severity levels stay
  defined, and that `examples/sample-review.md` uses only defined labels.
- `examples/sample-review.md` rewritten into the three buckets. It previously used ad-hoc
  `BLOCKING`/🟠/🟡 markers whose verdict text disagreed with them (two 🟠 items were called
  "medium", 🟡 "low"). It now demonstrates a failed rejection gate as a gate rather than as a
  "Critical" finding, shows a cited basis on every severity, shows a CWE cited on three defects
  and explicitly absent on the fourth, includes an "assessed and not raised" entry so a scanner
  suppression is accounted for rather than silently dropped, and keeps the Informational item
  visibly outside the blocking list.

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
