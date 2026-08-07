# Changelog

All notable changes to this skill are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Coverage for the OWASP GenAI/LLM and Agentic risk lists, which had never been walked.** The OWASP
  audit behind the current dimensions covered the **web-application** Top 10 only — yet the LLM/AI
  dimensions exist precisely because most Exchange listings are LLM agents with live tool access, so the
  most relevant lists were the unexamined ones. Walking the live **GenAI LLM Top 10 2026** (published
  2026-08-04, three days before this pass) and the draft **Top 10 for Agentic Applications** found 13 of
  20 categories already covered — several better than the web list was — and these real gaps, all closed
  as **prose in existing dimensions; no new rules and no new dimensions**:
  - **Hidden context exposure** (dim 13) — the *inverse* of injection, and the existing rules are blind
    to it by construction. The finding is not "the prompt can leak": assume it is discoverable. It is a
    **secret in the context** (credentials in a system prompt or tool description) or **a control that
    depends on secrecy** — authorization or content filtering enforced by prompt text is enforced by
    nothing, the dimension-17 "enforced control" bar applied to secrecy instead of authority. Lands
    hardest on MCP servers, which assemble tool schemas into the context by design.
  - **Agent memory and inter-agent messages** (dim 13) — two sinks the single-turn payload probe cannot
    reach. Anything the agent writes and reads back is **attacker-influenceable input on read-back**, by
    the same argument that makes a resource name untrusted; the probe needs a *second session* to show it.
    A message from another agent is not trusted merely because the sender is an agent.
  - **Human-approval integrity** (dim 17) — a control the design satisfies and the workflow defeats.
    Does the request show what is being approved, or a gloss written by the agent about to act on the
    answer? Can approval fatigue make it a rubber stamp? Can it be bypassed by delegation, a timing gap,
    or default-approve on timeout — which is dimension 3's fail-open defect in an authorization costume?
  - **Model and dataset provenance** (dim 18) — a model pulled by moving tag, or a prompt/tool manifest
    fetched from a remote endpoint, is an unpinned dependency in a registry nobody thinks to check; the
    last is also dimension 13's injection sink. `pinned-vuln-scan.py` reads package manifests and covers
    **none** of it, so a clean run says nothing.
  - **Two areas ruled OUT of scope, stated rather than left implied**: retrieval/vector internals (not
    assessed unless a listing ships an index — poisoned *content* is still covered by dim 13) and
    training-time model poisoning (these listings consume models, they do not train them).
  **Category names, never numbers**, and this pass produced fresh evidence for that rule: `Excessive
  Agency` moved LLM08 → LLM03 and `Insecure Output Handling` LLM02 → LLM10, and the OWASP draft itself
  contains a stale `LLM06:2025 Excessive Agency` citation. The agentic list is a **first public draft**
  whose expanded files are still unfilled templates — real content lives only in the superseded 0.5
  candidates — so no ASI ids are cited anywhere and nothing is gated against it.
- **`gate2e`** (suite 171 → **172**): every helper script `SKILL.md` cites must exist. Same defect class
  as `gate2d` with a worse consequence — the prose tells reviewers to *run* these, so a stale citation
  fails mid-review. There was no check at all until a dimension-18 edit added a third
  `pinned-vuln-scan.py` citation. **Proven by breaking it**: renaming `tautology-scan.sh` made it fail
  naming the exact path. It requires the `scripts/` prefix, which is what excludes the Exchange's own
  `validator.py` (correctly not in this repo) and is also its documented blind spot.
- **OWASP 2025 mapping as per-rule metadata plus a pointer, deliberately not as a coverage table.** All
  15 rules now carry an `owasp:` key; the two dimension-11 test-hygiene rules state
  `no applicable category -- ...` explicitly, matching the idiom their `cwe:` field already used, because
  an absent key is indistinguishable from an unmapped one. `SKILL.md` gains a short pointer saying the
  per-category view is **derivable** (`grep owasp: scripts/semgrep-rules/*.yaml`) and that the skill is
  organized by dimension and CWE, not by framework. **No table ships**, for the same reason the Exchange
  checklist is not embedded: a copy of a list maintained elsewhere goes stale silently while still reading
  as current, and a mapping table becomes wrong the moment a rule is added — dimension 12's own failure
  mode. Categories are cited by **name, not number**, since four numbers moved between the 2021 and 2025
  lists and a stale "A10 SSRF" now misleads. The pointer also states what the metadata cannot: an absent
  `owasp:` value means no *rule* maps to a category, not that the dimension set misses it — A03 is a
  standalone probe, A06 a documented rejection, A07 and A09 prose-only by measurement, and A04/A08 lean
  partly on `bandit`'s rule ids.
- **`gate2c` and `gate2d`** (suite 169 → **171**), because the pointer above is a claim and this repo's
  own rule is that a claim needs a gate. `gate2c` fails if any rule omits `owasp:` — the derive-on-demand
  trade only holds while the metadata is complete. `gate2d` fails if a rule id cited in `SKILL.md`
  resolves to no file. Both were **proven by breaking them**: removing one `owasp:` key and renaming one
  cited id made each gate fail naming the exact cause.
- **Three TypeScript counterparts for Python-only rules, each measured against the 1074-file MCP corpus
  before it was considered done.** 12 rules → **15**. Authoring and measuring is one task here, because
  `ts-binds-all-interfaces` (below) proved that a rule the corpus has never seen can ship looking
  complete while missing every real site.
  - **`ts-failopen-on-exception`** (dim 3, CWE-636). Matches a `catch` that returns `true` or `[]`.
    The corpus was measured *first*: 33 permissive catch returns in 21 files, distributed **null: 18,
    undefined: 11, []: 4, true: 0** — matching `null`/`undefined` would have made the rule ~88% noise,
    so that exclusion is a measurement rather than a preference. `true` measured zero and is kept anyway
    as the highest-severity shape at no FP cost. Four pattern branches, not two, because `catch { }` and
    `catch ($E) { }` are **different patterns** to semgrep: measured, the unbound form alone matched
    probe lines [1,3] and missed [2,4]. All 4 corpus hits are the documented honest-absent-collection
    FP class, cited by file and line.
  - **`ts-ssrf-url-from-scanned-data`** (dim 2/17, CWE-918). Nine sinks across `fetch`/`axios`/`got`/
    `http.request`. **The noisiest rule in the set, deliberately**: 182 corpus findings, cut to 60 by a
    test-file `paths:` filter and two provably-safe URL exclusions (literal host with interpolated
    path/port/query, and relative URLs). It stays at that volume because **154 of the 182 pass a bare
    variable** that no syntactic rule can resolve, so its output is a queue of one question — *where does
    the host come from?* `examples/` is **not** excluded, costing 14 findings of noise, because example
    code in a submission is code users copy. Carries the ruleset's only `paths:` filter, with the
    divergence and a verified no-silent-zero check recorded in its header.
  - **`ts-path-write-without-containment`** (dim 2, CWE-22). Seven `fs` write sinks. Guard spellings were
    **grepped from the corpus before being written**, not imagined: `startsWith(resolve(DIR) + sep)`,
    `startsWith(ROOT + path.sep)`, and `path.relative(base, dest).startsWith("..")`. 43 findings, 11
    outside tests. Its most instructive hit is a **false positive** — `servers/.../lib.ts:165` writes an
    unguarded parameter whose sole caller validates the path one frame up, verified by reading both call
    sites. The header states plainly that an accepted guard may still be **wrong**: `startsWith(base)`
    without the trailing separator lets `/data/output-evil` past a check against `/data/out`.
  - **24 new `MUTS` rows and Gate 5b green.** Every one of the 24 fixture findings these rules add is
    neutralized by its own row, so each pattern branch has a committed test. Gate 5b caught two real
    gaps while this landed — a row whose anchor text no longer matched, and one whose replacement
    truncated a trailing comment into invalid TypeScript. Suite: 145 → **169 tests**.
  - **Adversarial ablation of all 30 pattern elements across the three rules, run to completion rather
    than sampled.** Every sink, exclusion, and guard was removed individually and required to change the
    fixture result. First pass found **6 inert elements** — 3 sink literal-exclusions covering sinks the
    fixture never called, 1 unexercised `axios.get` branch, and 2 `metavariable-regex` blocks (below) —
    all fixed by extending the fixtures or deleting the pattern. Final state: **0 inert**.
- **A fourth counterpart was scoped and deliberately not written.** A TS version of
  `py-caseless-string-case-check` would be a rule for a bug that does not exist: in Python
  `"123".islower()` and `"123".isupper()` are *both* False, which is what makes the check wrong, but in
  JS `s === s.toLowerCase()` is **true** for `"123"`. The semantics are inverted, not transplanted.
- **Gate 5b: mutation coverage at *finding* granularity, and a paired proof that it works.** Gate 5's
  coverage check asserted only that every rule appears in the mutation table — satisfied by a single
  row. So editing a rule to add a new `pattern-either` branch could ship with **no test covering the
  new branch** and the suite would still print all-green. That is not hypothetical: the
  framework-factory fix below added **3 fixture findings and 0 mutation rows**, and Gate 5 passed. The
  ablation that proved the branch worked was run by hand and never committed, so nothing in the suite
  reproduced it. Gate 5b now requires **every baseline fixture finding to be neutralized by some
  mutation row**; a finding no row can remove is a matcher branch with no committed test. Measured when
  added: **11 such findings across 6 rules**, 4 of them in the rule that had just been edited — rows
  added for all 11. `gate5b-self` reproduces the historical defect (drops the 3 factory rows from the
  manifest) and requires Gate 5b to fail naming lines 43, 48, 55; it also fails loudly if the ablation
  turns out to be a no-op, so it cannot pass vacuously. It reuses the existing batch scan and manifest
  rather than re-scanning, so the proof costs no measurable wall clock. Suite: 132 → **145 tests**.

### Fixed
- **Three `SKILL.md` citations named only the Python rule after its TypeScript counterpart existed.**
  Dimension 2's SSRF bullet, dimension 3's fail-open bullet, and dimension 10's egress bullet all pointed
  at `py-*` alone, so a reviewer working a TypeScript submission — the artifact class the kit is mostly
  for — would not have learned the TS rule was there. Now cite both, with the TS rules' measured caveats
  at the point of use: the SSRF rule ships as a triage queue, and the fail-open rule's narrowness is the
  null:18/undefined:11/[]:4/true:0 corpus distribution rather than an oversight, so a `catch` returning
  `null` must be asked about by hand. Caught while auditing framework coverage, not by any check; the new
  `gate2d` catches only the harder-failing case where a cited id resolves to nothing.
- **A new gate's first version was wrong in a way only running it exposed.** `gate2d` initially scanned
  for `(py|ts)-[a-z0-9-]+` anywhere in `SKILL.md` and reported four dangling rule ids that were never
  citations: it had matched mid-word inside `cyberagents-exchange` (the skill's own name) and
  `happy-path-only`. Fixed to require a backtick span. Recorded because the gate looked obviously correct
  while being wrong, which is the argument for running a new check against known-bad input before
  trusting a pass.
- **A claim about JS/Python template-literal divergence was wrong, and the ablation caught it before it
  shipped.** The first draft of `ts-ssrf-url-from-scanned-data` carried two `metavariable-regex` blocks
  (`^`[^`$]*`$`) to exclude static template literals, on the stated belief that JS diverged from Python —
  that `"..."` would not match a template literal at all. Ablation showed both blocks were **inert**:
  removing them changed the fixture result not at all. Measured directly, `pattern-not: fetch("...", ...)`
  excludes a static template **and** still fires on an interpolating one, exactly the Python behaviour the
  sibling rule relies on. Both blocks were deleted and the header now records the corrected measurement
  in place of the wrong claim. The narrower trap that the draft was groping at is real and is documented
  instead: writing the exclusion with **backticks** suppresses all template literals including
  interpolated ones, which measurably hides a real SSRF and would have left the rule near-vacuous while
  looking complete.
- **A `paths:` filter that ablates as inert, because the ablation itself was measured wrong.**
  `ts-ssrf-url-from-scanned-data`'s test-file exclusion was re-measured four ways after the rules landed,
  and the result inverts the obvious reading: with an empty `.semgrepignore` in the corpus root the filter
  takes **173 findings / 1205 files down to 60 / 810**, but with semgrep's bundled ignore list active it
  reports **60 either way** — because that list already drops the same `tests/` directories. Anyone
  ablating the filter on a default checkout would correctly observe "no change" and delete something that
  removes 113 findings. `ts-path-write-without-containment` has the same dependency in milder form
  (41/880 without the override, 43/1205 with it), which matters more there because 32 of its 43 hits are
  in test files. Both rule headers now state the override alongside their numbers, and `CONTRIBUTING.md`
  makes it a rule: ablate a `paths:` filter with the override in place, or the measurement lies. This is
  the same silent-zero shape Gate 6 already tests for, arriving through the one path that made a
  *protective* pattern look useless rather than making a broken rule look fine.
- **`ts-binds-all-interfaces` had a blind spot that made its zero look like good news.** Measuring the
  TS rules against 1074 TypeScript files from six real MCP servers, this rule reported 0 findings — in a
  corpus containing **102 `.listen(` calls and 17 files mentioning `0.0.0.0`**. The previous header
  credited the empty result to the corpus, which was true of the browser-extension corpus it was written
  against and false here. The real cause: modern MCP servers bind through a framework *factory*
  (`createMcpExpressApp({ host: "0.0.0.0" })`), which has no `.listen` receiver for `$A.listen(...)` to
  bind, so the rule missed **8 real sites** in the current MCP TypeScript SDK. Replaced the narrow
  `$A.listen({...})` spelling with a receiver-less `$F({..., host: "0.0.0.0", ...})`, which subsumes it
  (measured: `server.listen({host: ...})` still matches). Paired test: ablating the new pattern makes
  `semgrep test` FAIL naming all four factory lines, so the guard is real. A rule that looked more
  precise simply did not match how the code it targets is written.

### Changed
- **Every TypeScript rule now carries a measurement against real MCP-server code**, closing the one
  place this repo made a weaker claim than its Python side (Python rules were measured against 65 real
  files; the TS rules had only planted fixtures). Corpus: the official `servers` and `typescript-sdk`
  repos plus context7, Figma-Context-MCP, mcp-server-cloudflare, and playwright-mcp. **13 of 1087 files
  failed to parse and were not analysed, so 1074 is the honest denominator** — a detail that would
  otherwise silently inflate every rate below. `github-mcp-server` was dropped from the corpus after
  inspection: it is Go with a 10-file TS UI, and counting it would have implied breadth it does not add.

  | Rule | Findings | Reading |
  |---|---|---|
  | `ts-wildcard-cors` | **13** (8 production) | highest-firing; all genuine. Near house style on MCP servers, since browser clients need cross-origin access to OAuth metadata and token endpoints. Three intents now documented — reasoned, self-flagged, and unremarked — because only the third is usually worth raising |
  | `ts-binds-all-interfaces` | **8** (0 production) | all in `.examples.`/guide files, 6 pairing the broad bind with an `allowedHosts` allowlist. Found only after the fix above |
  | `ts-weak-hash-or-random` | **3** (2 production) | all three false positives — see the near-miss below |
  | `ts-unsafe-deserialization` | 0 | corpus has no `eval` / `new Function` / unsafe deserializer, and vendors nothing |
  | `ts-untrusted-data-in-llm-system-prompt` | 0 | **34 files do contain a system-prompt channel** — an 8.5x better denominator than the previous measurement's 4, with no misfires |
  | `ts-token-in-localstorage` | 0 | **vacuous**: 0 occurrences of `localStorage`/`sessionStorage`, since a Node server has no DOM. Now documented as **N/A rather than passed** on submissions with no browser surface |
  | `ts-tls-verification-disabled` | 0 | **vacuous**: 0 occurrences of `rejectUnauthorized` in any form, twice over now |

  Every one of the 25 findings was triaged by reading the source; none is reported on a count alone.
- **A documented near-miss in `ts-weak-hash-or-random`'s header — the most instructive hit this rule has
  produced, and it is a false positive.** `typescript-sdk/packages/client/src/client/authExtensions.ts:50`
  derives the `jti` claim of a private-key-JWT client assertion (RFC 7523) from `Math.random()`. Every
  surface signal says High: an auth file, a named security claim, a citable RFC, `Math.random()` where a
  CSPRNG was already proven available. **It was initially written up here as a real defect. That was
  wrong**, and checking the specs rather than reasoning from the claim's name is what overturned it:
  RFC 7519 §4.1.7 requires only that `jti` have a negligible probability of being *accidentally*
  duplicated — collision resistance, not unpredictability; RFC 7523 §3(7) makes AS-side replay tracking
  a MAY and §6 says the spec does not mandate replay protection; RFC 8725 does not mention `jti` at all
  (its entropy requirements cover keys and ECDSA nonces). The attack path also does not close: replaying
  the captured assertion verbatim reuses the same `jti` and is rejected anyway, while forging a new one
  — or pre-burning a predicted value to lock the real client out — requires the client's private key.
  **The signature is the control on every path; `jti` is bookkeeping.** Measured on the property that is
  actually required: 0 collisions in 2,000,000 generated values. Correct verdict:
  `crypto.randomUUID()` would be better and more consistent with the same repo's session-id generation,
  but this is a code-quality nit, not a vulnerability.
  Revised tally: across both corpora this rule has **17 findings and 0 confirmed defects**, which
  *confirms* rather than softens its documented "mostly right about the construct, mostly wrong about the
  risk." The header now carries the triage rule the episode produced: for a `Math.random()` hit, ask
  **which property the consumer requires** — uniqueness (`jti`, ETags, idempotency keys, cache busters)
  or unpredictability (session tokens, API keys, reset links, CSRF tokens, nonces) — and read the spec
  instead of inferring it from the field's name. Only the second class is a defect. A value whose name
  *sounds* like a security control is the easiest way to talk yourself into a finding that is not there.
- **A second false-positive class for `py-failopen-on-exception`**, from the `servers` repo's Python git
  server: `except git.InvalidGitRepositoryError: pass` inside a loop that is *filtering* candidate paths.
  Same syntax as the defect, opposite meaning; the distinguishing feature is that the handler discards a
  loop iteration rather than a security decision, which no pattern can see. Deliberately **not**
  excluded — an exclusion keyed on that shape would suppress real fail-opens in retry and per-item
  authorization loops. Documented with a triage heuristic instead: if the `try` body appends to a
  collection on success it is probably a filter; if it guards something it is probably a fail-open.
- **`SKILL.md` gains the three-question drill for a zero** (does the rule fire on its own fixture, does
  the construct appear in the corpus, and if both — why is the count zero?), plus the MCP-specific
  guidance above. Skipping the third question is this skill's own dimension 1 turned on its tooling.
- **Corrected a false explanation in `ts-tls-verification-disabled`'s header.** It claimed JS corpora
  hold no server-side configuration, and used that to excuse the zeros in `ts-wildcard-cors` and
  `ts-binds-all-interfaces`. Both fired on this corpus (13 and 8). The reasoning was true of browser
  extensions and false of MCP servers; it is corrected in place rather than deleted, since it was the
  argument used to wave two zeros through.

## [1.2.0] — 2026-08-07

### Added
- **CI job: release consistency (tags ↔ CHANGELOG).** Added because this repo drifted exactly the way
  it warns others about: commit `63e4fa0` was titled "Release 1.1.0" and shipped a `## [1.1.0]`
  CHANGELOG section, but no `v1.1.0` tag was ever created — so for three days the repo asserted a
  release that did not exist, while 12 commits accumulated past the last real tag. Dimension 12
  (overstated coverage) and dimension 18 (provenance) both name that shape and nothing was checking
  for it here. Three bidirectional checks, because the drift can start from either side: a pushed tag
  must have a CHANGELOG section; a commit claiming `Release X.Y.Z` must have the tag; a CHANGELOG
  section for a version must have the tag. The last two run on **every** trigger, not just tag
  pushes, so drift surfaces on the PR that introduces it rather than at release time.
  One narrow carve-out, on `pull_request` only: a version section the PR *itself* adds may be
  untagged, since the tag has to point at a merge commit that does not exist yet. Without it every
  release PR would be red by construction and the only way to ship would be to merge a red
  pipeline — which `CONTRIBUTING.md` forbids, so the gate would have forced a violation of this
  repo's own rule. The carve-out is scoped by diffing the base branch's `CHANGELOG.md`, so a section
  already on `main` and still untagged remains an error; an unreadable base fails loudly rather than
  exempting everything, which would have quietly turned the carve-out into a blanket bypass.
  Seven measured cases, not assumed: the release PR passes; **the `63e4fa0` defect still fails with
  the carve-out active** (the control that matters); an untagged section on a `main` push fails; a
  `v9.9.9` tag with no CHANGELOG section fails; a bogus base SHA fails loudly; and the post-tag state
  passes on both `main` and tag-push triggers. The embedded Python was also extracted back out of the
  YAML and compiled, because a heredoc that silently breaks reads as *passing*.
  The workflow now also triggers on `push: tags: ['v*']`.
- **`CONTRIBUTING.md` documents how to cut a release**, including the ordering constraint the CI
  check imposes (merge the CHANGELOG rename *before* tagging), the PR-only carve-out, the brief
  window where `main` is legitimately red between merge and tag push, and how to pick the bump.
- **Tags `v1.1.0` and `v1.2.0`.** `v1.1.0` is back-filled onto `63e4fa0`, the commit that documented
  it — accurate rather than retroactive, since the `## [1.1.0]` section has existed since 2026-08-04.
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
- **Two rules and three prose sections closing the OWASP 2025 gaps found by an earlier audit**
  (`A01` SSRF, `A09` logging/alerting, `A10` mishandling of exceptional conditions). The audit had
  mapped all ten 2025 categories against the 19 dimensions; these were the three that came back as
  real gaps rather than already-covered-under-another-name. Rule count 10 → 12, test suite 123 → 132.
  - **`semgrep-rules/py-ssrf-url-from-scanned-data`** (dim 2/17, `CWE-918`) — outbound request to a
    non-literal URL with no host allowlist in the same function. This matters for this artifact class
    specifically: these tools read attacker-influenceable cloud metadata and then fetch what it names,
    so an `evidence_url` from a finding points wherever the environment says — including
    `169.254.169.254`, which returns the tool's own credentials. Catches all four planted defects
    (dict-derived URL, f-string host, `urlopen`, `httpx`) and clears all seven correct forms.
    **0 findings on 65 real Python files.** All 8 exclusions were ablation-measured to be
    load-bearing — two started out **inert**, and rather than ship patterns that look protective and
    do nothing, the fixture gained the two real safe shapes (`httpx` constant, `requests.request`
    generic verb) that make them fire. This is the third time an exclusion has been measured rather
    than assumed here, and the second time the measurement changed what shipped.
  - **`semgrep-rules/py-failopen-on-exception`** (dim 3, `CWE-636`, OWASP A10) — an exception handler
    that returns a **permissive** value: `True` reading as "compliant", `[]` reading as "no findings",
    or a bare `pass`. Dimension 3 asked whether the tool fails *cleanly* and never asked whether it
    fails *closed* — so a scanner that reports a clean bill of health for an environment it never
    examined passed the dimension. Catches all three shapes, clears both correct forms.
    The leading `...` inside each handler pattern is **load-bearing and measured**: without it the
    `log.warning(); return []` case is missed (control finds 3 defects, ablated finds 2) — and that
    is the commonest real spelling, because the log line is what convinces the author they handled it.
    **1 finding on 65 real Python files**, the predicted `except ImportError: pass`
    optional-dependency probe, now excluded. That exclusion is deliberately **broader than the FP**:
    it also suppresses a security module silently failing to import, which is a genuine fail-open. A
    narrower `try: import $M ... except ImportError: pass` form was written and **measured to be
    equivalent** (it suppressed the security-import probe identically, since the import is the first
    statement either way), so it was discarded rather than shipped as a distinction that does not
    exist. The blind spot is named in the rule header instead.
  - **Overlap is measured, not asserted**, because both rules sit next to tools that look like they
    already cover them. `bandit` B310 fires on the SSRF fixture's `urlopen` lines — *and on the
    correct constant-URL line*, because it audits the URL **scheme**, not the URL's provenance; it
    does not cover `requests` or `httpx` at all. `bandit` B110 sees 1 of the 3 fail-open shapes
    (`try/except/pass`); `ruff` BLE001/S110 flag the *style* of a blind except. None of them
    distinguish a fail-open in a security decision from a benign one. Both findings are recorded in
    the rule headers so a future reader does not delete either rule as duplicative.
  - **Dimension 2 gains a URL sink**, structured like the path sink before it: the allowlist must be
    on the parsed **hostname**, and the question the allowlist does not answer is redirects — an
    allowlisted host can 302 to a blocked one and `requests` follows redirects by default.
  - **Dimension 3 gains the fail-closed half and the A09 reconstruction/surfacing questions.** The
    A09 half is prose-only and stays that way: "sufficient logging" has no construct signature. The
    two questions worth asking are whether the output alone reveals what was **skipped** and why (a
    run that examined 3 of 40 accounts must not be reportable as "3 findings" — state the
    denominator), and whether anything makes a degraded run *visible* to someone who will never read
    stderr. Scheduled tools are the sharp case: nobody reads the logs of a job that exits 0.
  - **Dimension 10 gains the consequence for egress enumeration**: a destination is only enumerable
    if it is a constant. Where the target is computed from scanned data the egress set is unbounded,
    so the finding is the missing allowlist, not a documentation gap.

### Changed
- The shipped-helper directives and the CI comment no longer hardcode how many scripts ship
  ("these two" → "every script in `scripts/`"), so adding a scanner cannot leave a stale count.
- `setup.sh` now derives its brew list, its non-brew fallback list, and its status report from a
  single `TOOLS` variable. Previously four hand-maintained copies had to agree; editing one without
  the others meant a tool could install but never appear in the coverage report.
- **Gate 5 (the rule mutation loop) now runs as a single `semgrep scan` instead of one per row,
  cutting the helper-script suite from 6m27s to 1m45s** — a 3.7× speedup on the same 123 tests.
  Every baseline, mutant and negative control is staged into its own sibling directory under one
  tree and scanned together; findings are attributed back by `result.path`. A `semgrep scan` costs
  ~4.8s wall but only ~1.25s user, so ~95% was process startup — the win is from doing fewer scans,
  not faster ones. The feared trade did not materialise: every row still gets its own named
  PASS/FAIL line, because attribution is by directory rather than by invocation, and the 50 Gate 5
  verdict lines were diffed before and after the rewrite and are identical. Batch equivalence was
  measured before the rewrite landed: one all-rules scan reproduces the per-rule line sets exactly
  (47 findings, same 10 line lists), and a broken fixture in one directory does not poison its
  siblings. `gate5-self` — the check proving the gate catches a tautological rule — was deliberately
  moved *into* the same batch and judged by the same code path, since run separately it could have
  kept passing while the batched path was broken, silently disabling the check that proves the
  optimization safe. This also removes the runtime ceiling that was blocking further rules: the row
  count is now nearly free.

### Fixed
- `setup.sh --check` could **hang indefinitely**: it ran `<tool> --version` for each tool, and
  `semgrep --version` performs a network update check that never returns on a network that
  blackholes it (measured: >90s, no output, until killed). Version probes now pass
  `--disable-version-check` for semgrep and are wrapped in a 10s timeout for every tool, so one
  unresponsive binary degrades to `version probe timed out` instead of stalling the report.
  Verified with a stub whose `--version` sleeps 300s: the report completed in 14s.
- **A measurement error in how Gate 5's own guards were verified**, worth recording because the
  first answer was wrong and looked right. Mutating a guard and re-running the suite reports
  "survivor" for guards that are genuinely load-bearing: each one only fires on a defect that is not
  present, so disabling it on a healthy tree changes nothing (123 passed / 0 failed either way).
  An earlier run also compared suite totals from a harness that had copied `scripts/` without
  `setup.sh`, so six mutants "failed" at 114/9 for one shared environmental reason — `rc=127` — and
  were scored as caught. The honest test is **paired**: plant the defect, confirm the catch, then
  disable the guard and confirm the catch disappears. Under that test the per-path `errors` check,
  the negative-control `same` assertion, the staging-time no-op check (for negative-control rows) and
  the `gate5-self` inversion are all load-bearing, while the `scanned` and `found NOTHING` checks are
  diagnostics that name a cause another check would catch anyway. Each verdict is now recorded at the
  line it describes, so nobody re-derives it — or deletes a guard because mutation testing called it
  dead code.

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
