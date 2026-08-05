# Changelog

All notable changes to this skill are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/).

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
